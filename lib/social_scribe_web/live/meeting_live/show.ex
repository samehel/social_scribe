defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton

  alias SocialScribe.Automations
  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.Hubspot
  alias SocialScribe.HubspotOAuth
  alias SocialScribe.Meetings
  alias SocialScribe.Accounts
  alias SocialScribeWeb.MeetingLive.ContactSearchModalComponent

  require Logger

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:selected_hubspot_contact, nil)
        |> assign(:hubspot_field_updates, [])
        |> assign(:hubspot_field_update_error, nil)
        |> assign(:contact_search_component_id, contact_search_component_id(meeting))
        |> assign(:show_update_hubspot_modal, false)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => meeting.follow_up_email || ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_update_hubspot_modal", _params, socket) do
    {:noreply, assign(socket, :show_update_hubspot_modal, true)}
  end

  @impl true
  def handle_event("close_update_hubspot_modal", _params, socket) do
    {:noreply, assign(socket, :show_update_hubspot_modal, false)}
  end

  @impl true
  def handle_info(
        {ContactSearchModalComponent, :search_contacts, %{query: query}},
        socket
      ) do
    trimmed = String.trim(query || "")
    component_id = socket.assigns.contact_search_component_id

    cond do
      trimmed == "" ->
        send_update(ContactSearchModalComponent,
          id: component_id,
          results: [],
          error: nil
        )

        {:noreply, socket}

      true ->
        case Accounts.get_user_credential(socket.assigns.current_user, "hubspot")
             |> fetch_hubspot_contacts(trimmed) do
          {:ok, results} ->
            send_update(ContactSearchModalComponent,
              id: component_id,
              results: results,
              error: nil
            )

            {:noreply, socket}

          {:error, :missing_credential} ->
            send_update(ContactSearchModalComponent,
              id: component_id,
              results: [],
              error: "Connect your HubSpot account to search contacts."
            )

            {:noreply, socket}

          {:error, :missing_refresh_token} ->
            send_update(ContactSearchModalComponent,
              id: component_id,
              results: [],
              error: "HubSpot refresh token missing. Please reconnect your account."
            )

            {:noreply, socket}

          {:error, {:refresh_failed, reason}} ->
            Logger.warning("HubSpot token refresh failed", reason: inspect(reason))

            send_update(ContactSearchModalComponent,
              id: component_id,
              results: [],
              error: "Could not refresh HubSpot connection. Please reconnect and try again."
            )

            {:noreply, socket}

          {:error, {:api_error, status, body}} ->
            Logger.warning("HubSpot contact search API error", status: status, body: body)

            send_update(ContactSearchModalComponent,
              id: component_id,
              results: [],
              error: "HubSpot search failed (status #{status})."
            )

            {:noreply, socket}

          {:error, {:http_error, reason}} ->
            Logger.error("HubSpot contact search HTTP error", reason: inspect(reason))

            send_update(ContactSearchModalComponent,
              id: component_id,
              results: [],
              error: "Unable to reach HubSpot. Please try again."
            )

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_info(
        {ContactSearchModalComponent, :update_hubspot_contact, %{updates: updates}},
        socket
      ) do
    component_id = socket.assigns.contact_search_component_id

    # Collect only selected updates
    selected_updates = Enum.filter(updates, & &1.selected)

    if Enum.empty?(selected_updates) do
      send_update(ContactSearchModalComponent,
        id: component_id,
        field_update_error: "Please select at least one field to update."
      )

      {:noreply, socket}
    else
      # Build properties map from selected updates
      properties =
        selected_updates
        |> Enum.map(fn update -> {to_string(update.field), update.new_value} end)
        |> Map.new()

      contact_id = socket.assigns.selected_hubspot_contact["id"]

      case Accounts.get_user_credential(socket.assigns.current_user, "hubspot")
           |> update_hubspot_contact(contact_id, properties) do
        {:ok, _updated_contact} ->
          socket =
            socket
            |> put_flash(:info, "Successfully updated #{length(selected_updates)} field(s) in HubSpot.")
            |> assign(:show_update_hubspot_modal, false)
            |> reset_field_update_assigns()

          {:noreply, socket}

        {:error, :missing_credential} ->
          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: "Connect your HubSpot account to update contacts."
          )

          {:noreply, socket}

        {:error, :missing_refresh_token} ->
          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: "HubSpot refresh token missing. Please reconnect your account."
          )

          {:noreply, socket}

        {:error, {:refresh_failed, reason}} ->
          Logger.warning("HubSpot token refresh failed during update", reason: inspect(reason))

          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: "Could not refresh HubSpot connection. Please reconnect and try again."
          )

          {:noreply, socket}

        {:error, {:api_error, status, body}} ->
          Logger.warning("HubSpot contact update API error", status: status, body: body)

          error_message =
            case body do
              %{"message" => msg} -> "HubSpot update failed: #{msg}"
              _ -> "HubSpot update failed (status #{status})."
            end

          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: error_message
          )

          {:noreply, socket}

        {:error, {:http_error, reason}} ->
          Logger.error("HubSpot contact update HTTP error", reason: inspect(reason))

          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: "Unable to reach HubSpot. Please try again."
          )

          {:noreply, socket}

        {:error, :empty_properties} ->
          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: "No valid properties to update."
          )

          {:noreply, socket}

        {:error, :invalid_contact_id} ->
          send_update(ContactSearchModalComponent,
            id: component_id,
            field_update_error: "Invalid contact ID. Please select a contact again."
          )

          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info(
        {ContactSearchModalComponent, :field_updates_toggled, %{updates: updates}},
        socket
      ) do
    send_update(ContactSearchModalComponent,
      id: socket.assigns.contact_search_component_id,
      field_updates: updates
    )

    {:noreply, assign(socket, :hubspot_field_updates, updates)}
  end

  @impl true
  def handle_info(
        {ContactSearchModalComponent, :contact_selected, %{id: contact_id}},
        socket
      ) do
    component_id = socket.assigns.contact_search_component_id

    case Accounts.get_user_credential(socket.assigns.current_user, "hubspot")
         |> fetch_hubspot_contact_details(contact_id) do
      {:ok, contact} ->
        {field_updates, field_update_error} =
          case fetch_ai_field_updates(socket.assigns.meeting, contact) do
            {:ok, updates} ->
              {prepare_field_updates(socket.assigns.meeting, contact, updates), nil}

            {:error, reason} ->
              Logger.warning("AI field update suggestions failed", reason: inspect(reason))
              {[], field_update_error_message(reason)}
          end

        send_update(ContactSearchModalComponent,
          id: component_id,
          selected_contact_id: contact_id,
          contact_details: contact,
          field_updates: field_updates,
          field_update_error: field_update_error,
          error: nil
        )

        {:noreply,
         socket
         |> assign(:selected_hubspot_contact, contact)
         |> assign(:hubspot_field_updates, field_updates)
         |> assign(:hubspot_field_update_error, field_update_error)}

      {:error, :missing_credential} ->
        send_update(ContactSearchModalComponent,
          id: component_id,
          selected_contact_id: nil,
          contact_details: nil,
          field_updates: [],
          field_update_error: nil,
          error: "Connect your HubSpot account to view contact details."
        )

        {:noreply, reset_field_update_assigns(socket)}

      {:error, :missing_refresh_token} ->
        send_update(ContactSearchModalComponent,
          id: component_id,
          selected_contact_id: nil,
          contact_details: nil,
          field_updates: [],
          field_update_error: nil,
          error: "HubSpot refresh token missing. Please reconnect your account."
        )

        {:noreply, reset_field_update_assigns(socket)}

      {:error, {:refresh_failed, reason}} ->
        Logger.warning("HubSpot contact refresh failed", reason: inspect(reason))

        send_update(ContactSearchModalComponent,
          id: component_id,
          selected_contact_id: nil,
          contact_details: nil,
          field_updates: [],
          field_update_error: nil,
          error: "Could not refresh HubSpot connection. Please reconnect and try again."
        )

        {:noreply, reset_field_update_assigns(socket)}

      {:error, {:api_error, status, body}} ->
        Logger.warning("HubSpot contact fetch API error", status: status, body: body)

        send_update(ContactSearchModalComponent,
          id: component_id,
          selected_contact_id: nil,
          contact_details: nil,
          field_updates: [],
          field_update_error: nil,
          error: "HubSpot contact fetch failed (status #{status})."
        )

        {:noreply, reset_field_update_assigns(socket)}

      {:error, {:http_error, reason}} ->
        Logger.error("HubSpot contact fetch HTTP error", reason: inspect(reason))

        send_update(ContactSearchModalComponent,
          id: component_id,
          selected_contact_id: nil,
          contact_details: nil,
          field_updates: [],
          field_update_error: nil,
          error: "Unable to reach HubSpot. Please try again."
        )

        {:noreply, reset_field_update_assigns(socket)}
    end
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  defp format_recorded_at(nil), do: "N/A"

  defp format_recorded_at(%DateTime{} = recorded_at) do
    DateTime.to_iso8601(recorded_at)
  end

  defp fetch_hubspot_contacts(nil, _query), do: {:error, :missing_credential}

  defp fetch_hubspot_contacts(credential, query) do
    with {:ok, credential} <- ensure_hubspot_credential_valid(credential),
         {:ok, results} <- do_hubspot_search_with_refresh(credential, query) do
      {:ok, results}
    else
      {:error, :missing_refresh_token} -> {:error, :missing_refresh_token}
      {:error, {:refresh_failed, _} = reason} -> {:error, reason}
      {:error, other} -> {:error, other}
    end
  end

  defp fetch_hubspot_contact_details(nil, _contact_id), do: {:error, :missing_credential}

  defp fetch_hubspot_contact_details(credential, contact_id) do
    with {:ok, credential} <- ensure_hubspot_credential_valid(credential),
         {:ok, contact} <- do_hubspot_contact_fetch_with_refresh(credential, contact_id) do
      {:ok, contact}
    else
      {:error, :missing_refresh_token} -> {:error, :missing_refresh_token}
      {:error, {:refresh_failed, _} = reason} -> {:error, reason}
      {:error, other} -> {:error, other}
    end
  end

  defp do_hubspot_search_with_refresh(credential, query) do
    case Hubspot.search_contacts(credential.token, query, limit: 10) do
      {:ok, results} ->
        {:ok, results}

      {:error, {:api_error, status, _body}} when status in [401, 403] ->
        with {:ok, refreshed} <- refresh_hubspot_credential(credential),
             {:ok, results} <- Hubspot.search_contacts(refreshed.token, query, limit: 10) do
          {:ok, results}
        else
          {:error, :missing_refresh_token} -> {:error, :missing_refresh_token}
          {:error, {:api_error, status, body}} -> {:error, {:api_error, status, body}}
          {:error, {:http_error, reason}} -> {:error, {:http_error, reason}}
          {:error, other} -> {:error, {:refresh_failed, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_hubspot_contact_fetch_with_refresh(credential, contact_id) do
    case Hubspot.get_contact(credential.token, contact_id) do
      {:ok, contact} ->
        {:ok, contact}

      {:error, {:api_error, status, _body}} when status in [401, 403] ->
        with {:ok, refreshed} <- refresh_hubspot_credential(credential),
             {:ok, contact} <- Hubspot.get_contact(refreshed.token, contact_id) do
          {:ok, contact}
        else
          {:error, :missing_refresh_token} -> {:error, :missing_refresh_token}
          {:error, {:api_error, status, body}} -> {:error, {:api_error, status, body}}
          {:error, {:http_error, reason}} -> {:error, {:http_error, reason}}
          {:error, other} -> {:error, {:refresh_failed, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_hubspot_credential_valid(%{expires_at: nil} = credential), do: {:ok, credential}

  defp ensure_hubspot_credential_valid(%{expires_at: expires_at} = credential) do
    case DateTime.compare(expires_at, DateTime.utc_now()) do
      :gt -> {:ok, credential}
      _ -> refresh_hubspot_credential(credential)
    end
  end

  defp refresh_hubspot_credential(credential) do
    case HubspotOAuth.refresh_access_token(credential) do
      {:ok, token_data} ->
        case Accounts.update_credential_tokens(credential, token_data) do
          {:ok, updated_credential} -> {:ok, updated_credential}
          {:error, changeset} -> {:error, {:refresh_failed, changeset}}
        end

      {:error, :missing_refresh_token} ->
        {:error, :missing_refresh_token}

      {:error, {:api_error, status, body}} ->
        {:error, {:refresh_failed, {:api_error, status, body}}}

      {:error, {:http_error, reason}} ->
        {:error, {:refresh_failed, {:http_error, reason}}}
    end
  end

  defp update_hubspot_contact(nil, _contact_id, _properties), do: {:error, :missing_credential}

  defp update_hubspot_contact(credential, contact_id, properties) do
    with {:ok, valid_credential} <- ensure_hubspot_credential_valid(credential),
         {:ok, updated_contact} <- do_hubspot_contact_update_with_refresh(valid_credential, contact_id, properties) do
      {:ok, updated_contact}
    else
      {:error, :missing_refresh_token} -> {:error, :missing_refresh_token}
      {:error, {:refresh_failed, _} = reason} -> {:error, reason}
      {:error, other} -> {:error, other}
    end
  end

  defp do_hubspot_contact_update_with_refresh(credential, contact_id, properties) do
    case Hubspot.update_contact(credential.token, contact_id, properties) do
      {:ok, contact} ->
        {:ok, contact}

      {:error, {:api_error, status, _body}} when status in [401, 403] ->
        with {:ok, refreshed} <- refresh_hubspot_credential(credential),
             {:ok, contact} <- Hubspot.update_contact(refreshed.token, contact_id, properties) do
          {:ok, contact}
        else
          {:error, :missing_refresh_token} -> {:error, :missing_refresh_token}
          {:error, {:api_error, status, body}} -> {:error, {:api_error, status, body}}
          {:error, {:http_error, reason}} -> {:error, {:http_error, reason}}
          {:error, other} -> {:error, {:refresh_failed, other}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp contact_search_component_id(meeting) do
    "contact-search-modal-#{meeting.id}"
  end

  defp fetch_ai_field_updates(meeting, contact) do
    AIContentGeneratorApi.suggest_contact_field_updates(meeting, contact)
  end

  defp prepare_field_updates(meeting, contact, updates) do
    properties = Map.get(contact, "properties", %{})
    transcript_segments = meeting_transcript_segments(meeting)

    updates
    |> Enum.reduce({[], MapSet.new()}, fn update, {acc, seen} ->
      with field when is_binary(field) <- to_string(Map.get(update, "field")),
           cleaned_field <- String.trim(field),
           false <- cleaned_field == "",
           false <- MapSet.member?(seen, cleaned_field) do
        current_value = Map.get(properties, cleaned_field)
        new_value = Map.get(update, "new_value")

        # Skip if current value equals new value (normalize for comparison)
        if values_equal?(current_value, new_value) do
          {acc, seen}
        else
          timestamp = find_update_timestamp(transcript_segments, new_value, Map.get(update, "reason"))

          entry = %{
            field: cleaned_field,
            current_value: current_value,
            new_value: new_value,
            reason: Map.get(update, "reason"),
            confidence: Map.get(update, "confidence"),
            transcript_timestamp: timestamp,
            selected: true
          }

          {[entry | acc], MapSet.put(seen, cleaned_field)}
        end
      else
        _ -> {acc, seen}
      end
    end)
    |> then(fn {entries, _seen} -> Enum.reverse(entries) end)
  end

  defp values_equal?(val1, val2) do
    normalize_value(val1) == normalize_value(val2)
  end

  defp normalize_value(nil), do: ""
  defp normalize_value(""), do: ""
  defp normalize_value(val) when is_binary(val), do: String.trim(val)
  defp normalize_value(val), do: to_string(val) |> String.trim()

  defp meeting_transcript_segments(%{meeting_transcript: %{content: content}}) when is_map(content) do
    content
    |> transcript_data_from_content()
  end

  defp meeting_transcript_segments(_), do: []

  defp transcript_data_from_content(content) do
    case Map.get(content, "data") || Map.get(content, :data) do
      data when is_list(data) -> data
      _ -> []
    end
  end

  defp find_update_timestamp([], _value, _reason), do: nil

  defp find_update_timestamp(segments, value, reason) do
    normalized_value = normalize_search_value(value)

    cond do
      timestamp = locate_timestamp_for_value(segments, normalized_value) -> timestamp
      timestamp = locate_timestamp_for_reason(segments, reason) -> timestamp
      true -> nil
    end
  end

  defp normalize_search_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_search_value(_), do: nil

  defp locate_timestamp_for_value(_segments, nil), do: nil

  defp locate_timestamp_for_value(segments, value) do
    segments
    |> Enum.reduce_while(nil, fn segment, _acc ->
      segment_text = segment_text(segment)

      if segment_text && String.contains?(segment_text, value) do
        case segment_start_timestamp(segment) do
          nil -> {:cont, nil}
          seconds -> {:halt, format_transcript_timestamp(seconds)}
        end
      else
        {:cont, nil}
      end
    end)
  end

  defp locate_timestamp_for_reason(_segments, nil), do: nil

  defp locate_timestamp_for_reason(segments, reason) when is_binary(reason) do
    candidate =
      reason
      |> String.trim()
      |> extract_reason_candidate()

    locate_timestamp_for_value(segments, candidate)
  end

  defp locate_timestamp_for_reason(_segments, _), do: nil

  defp extract_reason_candidate(""), do: nil

  defp extract_reason_candidate(reason) do
    downcased = String.downcase(reason)

    cond do
      match = Regex.run(~r/'([^']+)'/, downcased) ->
        match |> List.last() |> String.trim()
      match = Regex.run(~r/"([^"]+)"/, downcased) ->
        match |> List.last() |> String.trim()
      true ->
        reason
        |> String.downcase()
        |> String.split(~r/[^a-z0-9\s]/)
        |> Enum.max_by(&String.length/1, fn -> "" end)
        |> String.trim()
    end
  end

  defp segment_text(segment) do
    words = Map.get(segment, "words") || Map.get(segment, :words) || []

    cond do
      is_list(words) and words != [] ->
        words
        |> Enum.map(fn word ->
          text = Map.get(word, "text") || Map.get(word, :text) || ""
          text |> String.trim() |> String.downcase()
        end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      text = Map.get(segment, "text") || Map.get(segment, :text) ->
        text |> String.trim() |> String.downcase()

      true ->
        nil
    end
  end

  defp segment_start_timestamp(segment) do
    words = Map.get(segment, "words") || Map.get(segment, :words) || []

    words
    |> Enum.map(fn word ->
      Map.get(word, "start_timestamp") || Map.get(word, :start_timestamp)
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        Map.get(segment, "start_timestamp") || Map.get(segment, :start_timestamp)

      timestamps ->
        Enum.min(timestamps)
    end
  end

  defp format_transcript_timestamp(nil), do: nil

  defp format_transcript_timestamp(seconds) when is_number(seconds) do
    total_seconds = seconds |> Float.floor() |> trunc()
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    secs = rem(total_seconds, 60)

    [hours, minutes, secs]
    |> Enum.map(&Integer.to_string(&1) |> String.pad_leading(2, "0"))
    |> Enum.join(":")
  end

  defp format_transcript_timestamp(_), do: nil

  defp field_update_error_message(nil), do: nil
  defp field_update_error_message(:no_transcript), do: "Meeting transcript unavailable, so AI suggestions could not be generated."

  defp field_update_error_message({:invalid_json, _reason}),
    do: "AI response was invalid. Please try again later."

  defp field_update_error_message({:unexpected_response_shape, _}),
    do: "AI response was not understood. Please try again later."

  defp field_update_error_message({:api_error, status, _body}),
    do: "AI service returned an error (status #{status})."

  defp field_update_error_message({:http_error, _reason}),
    do: "Unable to reach AI service. Check your connection and try again."

  defp field_update_error_message(other), do: "AI suggestions could not be generated (#{inspect(other)})."

  defp reset_field_update_assigns(socket) do
    socket
    |> assign(:selected_hubspot_contact, nil)
    |> assign(:hubspot_field_updates, [])
    |> assign(:hubspot_field_update_error, nil)
  end

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        is_map(assigns.meeting_transcript.content) &&
        (Map.get(assigns.meeting_transcript.content, "data") || Map.get(assigns.meeting_transcript.content, :data)) &&
        (is_list(Map.get(assigns.meeting_transcript.content, "data") || Map.get(assigns.meeting_transcript.content, :data)) &&
         Enum.any?(Map.get(assigns.meeting_transcript.content, "data") || Map.get(assigns.meeting_transcript.content, :data)))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <% transcript_data = Map.get(@meeting_transcript.content, "data") || Map.get(@meeting_transcript.content, :data) %>
          <div :for={segment <- transcript_data} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                <%=
                  cond do
                    participant = Map.get(segment, "participant") ->
                      Map.get(participant, "name") || "Unknown Speaker"

                    participant = Map.get(segment, :participant) ->
                      Map.get(participant, :name) || Map.get(participant, "name") || "Unknown Speaker"

                    true ->
                      Map.get(segment, "speaker") || Map.get(segment, :speaker) || "Unknown Speaker"
                  end
                %>:
              </span>
              <%= Enum.map_join(Map.get(segment, "words") || Map.get(segment, :words) || [], " ", fn word -> Map.get(word, "text") || Map.get(word, :text) || "" end) %>
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
