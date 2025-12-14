defmodule SocialScribe.CalendarSyncronizer do
  @moduledoc """
  Fetches and syncs Google Calendar events.
  """

  require Logger

  alias SocialScribe.GoogleCalendarApi
  alias SocialScribe.Calendar
  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.TokenRefresherApi

  @doc """
  Syncs events for a user.

  Currently, only works for the primary calendar and for meeting links that are either on the hangoutLink or location field.

  #TODO: Add support for syncing only since the last sync time and record sync attempts
  """
  def sync_events_for_user(user) do
    user
    |> Accounts.list_user_credentials(provider: "google")
    |> Task.async_stream(&fetch_and_sync_for_credential/1, ordered: false, on_timeout: :kill_task)
    |> Stream.run()

    {:ok, :sync_complete}
  end

  defp fetch_and_sync_for_credential(%UserCredential{} = credential) do
    with {:ok, token} <- ensure_valid_token(credential),
         {:ok, %{"items" => items}} <-
           GoogleCalendarApi.list_events(
             token,
             DateTime.utc_now() |> Timex.beginning_of_day() |> Timex.shift(days: -1),
             DateTime.utc_now() |> Timex.end_of_day() |> Timex.shift(days: 7),
             "primary"
           ),
         :ok <- sync_items(items, credential.user_id, credential.id),
         :ok <- delete_removed_events(items, credential.user_id) do
      :ok
    else
      {:error, reason} ->
        # Log errors but don't crash the sync for other accounts
        Logger.error("Failed to sync credential #{credential.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_valid_token(%UserCredential{} = credential) do
    if DateTime.compare(credential.expires_at || DateTime.utc_now(), DateTime.utc_now()) == :lt do
      if credential.refresh_token do
        case TokenRefresherApi.refresh_token(credential.refresh_token) do
          {:ok, new_token_data} ->
            {:ok, updated_credential} =
              Accounts.update_credential_tokens(credential, new_token_data)

            {:ok, updated_credential.token}

          {:error, reason} ->
            {:error, {:refresh_failed, reason}}
        end
      else
        {:error, {:refresh_failed, "No refresh token available. Please reconnect your account."}}
      end
    else
      {:ok, credential.token}
    end
  end

  defp sync_items(items, user_id, credential_id) do
    Enum.each(items, fn item ->
      location = Map.get(item, "location", "")
      hangout_link = Map.get(item, "hangoutLink")

      has_zoom = String.contains?(location, ".zoom.")
      has_google_meet = hangout_link != nil
      has_teams = String.contains?(location, "teams.microsoft.com")

      if has_zoom || has_google_meet || has_teams do
        parsed_event = parse_google_event(item, user_id, credential_id)

        # Check if event exists and log time changes
        existing_event = Calendar.get_calendar_event_by_google_id(user_id, parsed_event.google_event_id)

        if existing_event do
          log_time_changes_if_significant(existing_event, parsed_event)
        end

        Calendar.create_or_update_calendar_event(parsed_event)
      end
    end)

    :ok
  end

  defp parse_google_event(item, user_id, credential_id) do
    start_time_str = Map.get(item["start"], "dateTime", Map.get(item["start"], "date"))
    end_time_str = Map.get(item["end"], "dateTime", Map.get(item["end"], "date"))

    hangout_link =
      Map.get(item, "hangoutLink") ||
        Map.get(item, "location") ||
        Map.get(item, "description") ||
        ""

    %{
      google_event_id: item["id"],
      summary: Map.get(item, "summary", "No Title"),
      description: Map.get(item, "description"),
      location: Map.get(item, "location"),
      html_link: Map.get(item, "htmlLink"),
      hangout_link: hangout_link,
      status: Map.get(item, "status"),
      start_time: to_utc_datetime(start_time_str),
      end_time: to_utc_datetime(end_time_str),
      user_id: user_id,
      user_credential_id: credential_id
    }
  end

  defp to_utc_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        nil
    end
  end

  defp log_time_changes_if_significant(existing_event, new_event_data) do
    # Minimum time difference to consider significant: 5 minutes (300 seconds)
    min_diff_seconds = 300

    start_diff =
      if existing_event.start_time && new_event_data.start_time do
        abs(DateTime.diff(existing_event.start_time, new_event_data.start_time))
      else
        0
      end

    end_diff =
      if existing_event.end_time && new_event_data.end_time do
        abs(DateTime.diff(existing_event.end_time, new_event_data.end_time))
      else
        0
      end

    cond do
      start_diff >= min_diff_seconds && end_diff >= min_diff_seconds ->
        Logger.info(
          "Calendar event time changed: '#{existing_event.summary}' (ID: #{existing_event.id}) - " <>
          "Start moved by #{div(start_diff, 60)} minutes, End moved by #{div(end_diff, 60)} minutes"
        )

      start_diff >= min_diff_seconds ->
        Logger.info(
          "Calendar event start time changed: '#{existing_event.summary}' (ID: #{existing_event.id}) - " <>
          "Moved by #{div(start_diff, 60)} minutes"
        )

      end_diff >= min_diff_seconds ->
        Logger.info(
          "Calendar event end time changed: '#{existing_event.summary}' (ID: #{existing_event.id}) - " <>
          "Moved by #{div(end_diff, 60)} minutes"
        )

      true ->
        # No significant change
        :ok
    end
  end

  defp delete_removed_events(google_items, user_id) do
    # Get all google_event_ids from the API response
    google_event_ids = Enum.map(google_items, & &1["id"]) |> MapSet.new()

    # Get all upcoming calendar events for this user from database
    time_range_start = DateTime.utc_now() |> Timex.beginning_of_day() |> Timex.shift(days: -1)
    time_range_end = DateTime.utc_now() |> Timex.end_of_day() |> Timex.shift(days: 7)

    db_events = Calendar.list_calendar_events_in_range(user_id, time_range_start, time_range_end)

    # Find events in database that are NOT in Google Calendar anymore
    # But never delete events that have completed meetings
    events_to_delete =
      Enum.filter(db_events, fn event ->
        not MapSet.member?(google_event_ids, event.google_event_id) and
        not Calendar.has_completed_meeting?(event)
      end)

    # Delete each event with cascade (delete related records first)
    Enum.each(events_to_delete, fn event ->
      case Calendar.delete_calendar_event_cascade(event) do
        {:ok, _deleted} ->
          Logger.info("Deleted calendar event #{event.id} (#{event.summary}) - no longer in Google Calendar")

        {:error, reason} ->
          Logger.error("Failed to delete calendar event #{event.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
