defmodule SocialScribeWeb.HomeLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Calendar
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Bots
  alias SocialScribe.Meetings

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :sync_calendars)

    user = socket.assigns.current_user
    past_meeting_event_ids = get_past_meeting_event_ids(user)

    events =
      user
      |> Calendar.list_upcoming_events()
      |> filter_out_past_meetings(past_meeting_event_ids)

    socket =
      socket
      |> assign(:page_title, "Upcoming Meetings")
      |> assign(:events, events)
      |> assign(:past_meeting_event_ids, past_meeting_event_ids)
      |> assign(:loading, true)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_record", %{"id" => event_id}, socket) do
    event = Calendar.get_calendar_event!(event_id)

    {:ok, event} =
      Calendar.update_calendar_event(event, %{record_meeting: not event.record_meeting})

    send(self(), {:schedule_bot, event})

    updated_events =
      Enum.map(socket.assigns.events, fn e ->
        if e.id == event.id, do: event, else: e
      end)

    {:noreply, assign(socket, :events, updated_events)}
  end

  @impl true
  def handle_info({:schedule_bot, event}, socket) do
    if event.record_meeting do
      case Bots.create_and_dispatch_bot(socket.assigns.current_user, event) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Notetaker scheduled for this meeting")}

        {:error, reason} ->
          Logger.error("Failed to schedule bot: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to schedule notetaker. Check your Recall.ai configuration.")}
      end
    else
      case Bots.cancel_and_delete_bot(event) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Notetaker cancelled for this meeting")}

        {:error, reason} ->
          Logger.error("Failed to cancel bot: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to cancel notetaker")}
      end
    end
  end

  @impl true
  def handle_info(:sync_calendars, socket) do
    user = socket.assigns.current_user
    CalendarSyncronizer.sync_events_for_user(user)

    # Refresh past meeting IDs in case new meetings were added
    past_meeting_event_ids = get_past_meeting_event_ids(user)

    events =
      user
      |> Calendar.list_upcoming_events()
      |> filter_out_past_meetings(past_meeting_event_ids)

    socket =
      socket
      |> assign(:events, events)
      |> assign(:past_meeting_event_ids, past_meeting_event_ids)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  # Get calendar_event_ids for all past meetings
  defp get_past_meeting_event_ids(user) do
    user
    |> Meetings.list_user_meetings()
    |> Enum.map(& &1.calendar_event_id)
    |> MapSet.new()
  end

  # Filter out events that already have a meeting record
  defp filter_out_past_meetings(events, past_meeting_event_ids) do
    Enum.reject(events, fn event ->
      MapSet.member?(past_meeting_event_ids, event.id)
    end)
  end
end
