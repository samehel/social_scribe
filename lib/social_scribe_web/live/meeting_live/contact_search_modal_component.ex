defmodule SocialScribeWeb.MeetingLive.ContactSearchModalComponent do
  use SocialScribeWeb, :live_component

  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:results, fn -> [] end)
      |> assign_new(:selected_contact_id, fn -> nil end)
      |> assign_new(:contact_details, fn -> nil end)
      |> assign_new(:field_updates, fn -> [] end)
      |> assign_new(:field_update_error, fn -> nil end)
      |> assign_new(:selected_contact_label, fn -> nil end)
      |> assign_new(:search_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:expanded_fields, fn -> MapSet.new() end)
      |> assign(assigns)

    selected_label = selected_contact_label(socket.assigns[:contact_details])

    # Expand all fields by default when field_updates are present
    expanded_fields =
      if Map.has_key?(assigns, :field_updates) and is_list(assigns.field_updates) do
        assigns.field_updates
        |> Enum.map(& &1.field)
        |> MapSet.new()
      else
        socket.assigns.expanded_fields
      end

    socket =
      socket
      |> assign(:selected_contact_label, selected_label)
      |> assign(:expanded_fields, expanded_fields)

    {:ok, socket}
  end

  defp valid_avatar_url?(nil), do: false
  defp valid_avatar_url?(url) when is_binary(url), do: String.starts_with?(url, ["http://", "https://"])
  defp valid_avatar_url?(_), do: false

  defp initials("", nil), do: "?"
  defp initials("", email), do: email |> String.slice(0, 1) |> String.upcase()
  defp initials(name, _email) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.slice(&1, 0, 1))
    |> Enum.join()
    |> String.upcase()
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    trimmed_query = String.trim(query || "")

    send(self(), {__MODULE__, :search_contacts, %{query: trimmed_query, ref: socket.assigns.myself}})

    {:noreply,
     socket
     |> assign(:query, trimmed_query)
     |> assign(:error, nil)
     |> assign(:search_open, true)
     |> assign(:selected_contact_id, nil)
     |> assign(:contact_details, nil)
     |> assign(:selected_contact_label, nil)}
  end

  @impl true
  def handle_event("select_contact", %{"id" => id}, socket) do
    send(self(), {__MODULE__, :contact_selected, %{id: id}})

    {:noreply,
     socket
     |> assign(:selected_contact_id, id)
     |> assign(:search_open, false)}
  end

  @impl true
  def handle_event("toggle_field_update", %{"field" => field}, socket) do
    updated = toggle_field_update(socket.assigns.field_updates, field)

    send(self(), {__MODULE__, :field_updates_toggled, %{updates: updated}})

    {:noreply, assign(socket, :field_updates, updated)}
  end

  @impl true
  def handle_event("toggle_field_details", %{"field" => field}, socket) do
    expanded_fields = socket.assigns.expanded_fields

    updated_expanded =
      if MapSet.member?(expanded_fields, field) do
        MapSet.delete(expanded_fields, field)
      else
        MapSet.put(expanded_fields, field)
      end

    {:noreply, assign(socket, :expanded_fields, updated_expanded)}
  end

  @impl true
  def handle_event("update_hubspot_contact", _params, socket) do
    send(self(), {__MODULE__, :update_hubspot_contact, %{updates: socket.assigns.field_updates}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_single_field", %{"field" => field}, socket) do
    # Find the specific field update
    single_update = Enum.find(socket.assigns.field_updates, fn update ->
      to_string(update.field) == to_string(field)
    end)

    if single_update do
      # Send only this one field update, marked as selected
      send(self(), {__MODULE__, :update_hubspot_contact, %{updates: [%{single_update | selected: true}]}})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_contact_picker", _params, socket) do
    {:noreply, update(socket, :search_open, &(!&1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto w-full max-w-3xl">
      <div class="overflow-visible rounded-3xl border border-slate-100 bg-white shadow-[0_32px_64px_rgba(15,23,42,0.12)]">
        <div class="border-b border-slate-100 px-8 pt-8 pb-6">
          <h2 class="text-[26px] font-semibold leading-tight text-slate-900">Update in HubSpot</h2>
          <p class="mt-2 text-sm text-slate-500">
            Here are suggested updates to sync with your integrations based on this meeting.
          </p>
        </div>

        <div class="space-y-8 px-8 py-8 overflow-visible">
          <div class="relative space-y-3">
            <label class="text-xs font-semibold uppercase tracking-wide text-slate-400">Select Contact</label>

            <button
              type="button"
              phx-target={@myself}
              phx-click="toggle_contact_picker"
              class="flex w-full items-center justify-between rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-left shadow-inner transition hover:border-emerald-300"
            >
              <div class="flex min-w-0 items-center gap-3">
                <div class="flex h-10 w-10 items-center justify-center rounded-full bg-slate-200 text-sm font-semibold text-slate-600">
                  <img
                    :if={avatar_for_contact(@contact_details)}
                    src={avatar_for_contact(@contact_details)}
                    alt={@selected_contact_label || "Contact avatar"}
                    class="h-10 w-10 rounded-full object-cover"
                  />
                  <span :if={!avatar_for_contact(@contact_details)}>{selected_initials(@contact_details)}</span>
                </div>
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-slate-800">
                    {@selected_contact_label || "Select a contact"}
                  </p>
                  <p :if={selected_contact_email(@contact_details)} class="truncate text-xs text-slate-500">
                    {selected_contact_email(@contact_details)}
                  </p>
                  <p :if={!@selected_contact_label} class="text-xs text-slate-400">Search by name or email</p>
                </div>
              </div>
              <.icon name={@search_open && "hero-chevron-up-mini" || "hero-chevron-down-mini"} class="h-5 w-5 text-slate-400" />
            </button>

            <div
              :if={@search_open}
              class="absolute left-0 right-0 z-30 mt-3 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl"
            >
              <div class="border-b border-slate-100 p-4">
                <.form
                  for={%{"query" => @query}}
                  as={:search}
                  phx-change="search"
                  phx-target={@myself}
                  class="relative"
                >
                  <span class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                    <.icon name="hero-magnifying-glass-mini" class="h-5 w-5" />
                  </span>
                  <input
                    type="search"
                    name="search[query]"
                    value={@query}
                    placeholder="Search HubSpot contacts"
                    class="w-full rounded-xl border border-slate-200 bg-white py-3 pl-10 pr-4 text-sm text-slate-700 shadow-sm focus:border-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-100"
                    autocomplete="off"
                  />
                </.form>
              </div>

              <div class="max-h-64 overflow-y-auto p-2">
                <template :if={@error}>
                  <div class="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-600">
                    {@error}
                  </div>
                </template>

                <template :if={!@error && @query == "" && Enum.empty?(@results)}>
                  <p class="rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 text-center text-sm text-slate-500">
                    Start typing to search for HubSpot contacts.
                  </p>
                </template>

                <template :if={!@error && @query != "" && Enum.empty?(@results)}>
                  <p class="rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 text-center text-sm text-slate-500">
                    No contacts found.
                  </p>
                </template>

                <ul :if={!@error && Enum.any?(@results)} class="space-y-2">
                  <li
                    :for={contact <- @results}
                    class="rounded-xl border border-transparent">
                    <% properties = contact["properties"] || %{} %>
                    <% full_name =
                         [Map.get(properties, "firstname", ""), Map.get(properties, "lastname", "")]
                         |> Enum.reject(&(&1 == ""))
                         |> Enum.join(" ") %>
                    <% avatar =
                         [
                           Map.get(properties, "hs_avatar_filemanager_url"),
                           Map.get(properties, "hs_avatar_url"),
                           Map.get(properties, "photo")
                         ]
                         |> Enum.find(&valid_avatar_url?/1) %>

                    <button
                      type="button"
                      phx-click="select_contact"
                      phx-target={@myself}
                      phx-value-id={contact["id"]}
                      class={[
                        "flex w-full items-center justify-between gap-4 rounded-xl border border-slate-100 bg-white px-4 py-3 text-left shadow-sm transition hover:border-emerald-300 hover:shadow-md",
                        @selected_contact_id == contact["id"] && "border-emerald-300 ring-2 ring-emerald-200"
                      ]}
                    >
                      <div class="flex min-w-0 items-center gap-3">
                        <div class="flex h-10 w-10 items-center justify-center rounded-full bg-slate-200 text-sm font-semibold text-slate-600">
                          <img
                            :if={avatar}
                            src={avatar}
                            alt={full_name != "" && full_name || Map.get(properties, "email", "Contact avatar")}
                            class="h-10 w-10 rounded-full object-cover"
                          />
                          <span :if={!avatar}>
                            {initials(full_name, Map.get(properties, "email"))}
                          </span>
                        </div>
                        <div class="min-w-0">
                          <p class="truncate text-sm font-medium text-slate-800">
                            {full_name != "" && full_name || Map.get(properties, "email", "Unknown contact")}
                          </p>
                          <p class="truncate text-xs text-slate-500">
                            {Map.get(properties, "email", "Email not available")}
                          </p>
                        </div>
                      </div>
                      <span class="text-xs font-semibold uppercase tracking-wide text-emerald-600">
                        Select
                      </span>
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </div>

          <div :if={@field_update_error} class="rounded-2xl border border-amber-200 bg-amber-50 px-5 py-4 text-sm text-amber-700">
            {@field_update_error}
          </div>

          <div :if={!@field_update_error} class="space-y-6">
            <%= cond do %>
              <% Enum.any?(@field_updates) -> %>
                <div :for={update <- @field_updates} class="rounded-2xl border border-slate-200 bg-slate-50 px-6 py-5 shadow-sm">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div class="flex items-center gap-3">
                      <input
                        type="checkbox"
                        name="field_updates[]"
                        value={update.field}
                        checked={update.selected}
                        phx-click="toggle_field_update"
                        phx-target={@myself}
                        phx-value-field={update.field}
                        class="h-5 w-5 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                      <div class="text-base font-semibold text-gray-900">
                        {field_section_title(update.field)}
                      </div>
                    </div>
                    <div class="flex items-center gap-3 text-sm">
                      <span class="rounded-md bg-gray-100 px-2.5 py-1 text-sm font-medium text-gray-700">
                        {update_badge_label(@field_updates, update.field)}
                      </span>
                      <button
                        type="button"
                        phx-click="toggle_field_details"
                        phx-target={@myself}
                        phx-value-field={update.field}
                        class="text-sm text-gray-500 hover:text-gray-700"
                      >
                        {if MapSet.member?(@expanded_fields, update.field), do: "Hide details", else: "Show details"}
                      </button>
                    </div>
                  </div>

                  <div :if={MapSet.member?(@expanded_fields, update.field)} class="mt-5 space-y-3">
                    <p class="text-sm font-medium text-gray-900">{field_label(update.field)}</p>
                    <div class="flex items-start gap-3">
                      <input
                        type="checkbox"
                        name="field_updates_detail[]"
                        value={update.field}
                        checked={update.selected}
                        phx-click="toggle_field_update"
                        phx-target={@myself}
                        phx-value-field={update.field}
                        class="mt-1 h-5 w-5 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                      <div class="flex-1 grid gap-3 sm:grid-cols-[1fr_auto_1fr] sm:items-start">
                        <div class="space-y-2">
                          <input
                            type="text"
                            value={display_value(update.current_value)}
                            readonly
                            class="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900"
                          />
                          <button
                            type="button"
                            phx-click="update_single_field"
                            phx-target={@myself}
                            phx-value-field={update.field}
                            class="text-sm font-medium text-blue-600 hover:text-blue-700"
                          >
                            Update mapping
                          </button>
                        </div>
                        <div class="flex items-center justify-center py-2">
                          <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3" />
                          </svg>
                        </div>
                        <div class="space-y-2">
                          <input
                            type="text"
                            value={display_value(update.new_value)}
                            readonly
                            class="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-900"
                          />
                          <p :if={update.transcript_timestamp} class="text-sm text-blue-600">
                            Found in transcript ({update.transcript_timestamp})
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

              <% @selected_contact_label && Enum.empty?(@field_updates) -> %>
                <div class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 px-6 py-8 text-center text-sm text-slate-500">
                  No AI suggestions detected for this contact. Review the meeting transcript to confirm.
                </div>

              <% true -> %>
                <div class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 px-6 py-8 text-center text-sm text-slate-500">
                  Select a HubSpot contact to review suggested updates.
                </div>
            <% end %>
          </div>
        </div>

        <div class="flex flex-col gap-4 border-t border-gray-200 bg-white px-8 py-5 sm:flex-row sm:items-center sm:justify-between rounded-b-3xl">
          <p class="text-sm text-gray-600">{selection_summary(@field_updates)}</p>
          <div class="flex gap-3">
            <button
              type="button"
              class="inline-flex items-center justify-center rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50"
              phx-click={JS.push("close_update_hubspot_modal")}
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="update_hubspot_contact"
              phx-target={@myself}
              class="inline-flex items-center justify-center rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-emerald-700"
            >
              Update HubSpot
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_field_update(updates, field) do
    Enum.map(updates, fn update ->
      if to_string(update.field) == to_string(field) do
        Map.update!(update, :selected, &(!&1))
      else
        update
      end
    end)
  end

  defp display_value(nil), do: "—"
  defp display_value(""), do: "—"
  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: to_string(value)

  defp selected_contact_label(nil), do: nil

  defp selected_contact_label(%{"properties" => props}) do
    name =
      [Map.get(props, "firstname"), Map.get(props, "lastname")]
      |> Enum.filter(&(&1 not in [nil, ""]))
      |> Enum.join(" ")

    cond do
      name != "" -> name
      email = Map.get(props, "email") -> email
      true -> nil
    end
  end

  defp selected_contact_label(_), do: nil

  defp selected_contact_email(nil), do: nil
  defp selected_contact_email(%{"properties" => props}), do: Map.get(props, "email")
  defp selected_contact_email(_), do: nil

  defp avatar_for_contact(nil), do: nil

  defp avatar_for_contact(%{"properties" => props}) do
    [
      Map.get(props, "hs_avatar_filemanager_url"),
      Map.get(props, "hs_avatar_url"),
      Map.get(props, "photo")
    ]
    |> Enum.find(&valid_avatar_url?/1)
  end

  defp avatar_for_contact(_), do: nil

  defp selected_initials(nil), do: "?"

  defp selected_initials(%{"properties" => props}) do
    name =
      [Map.get(props, "firstname"), Map.get(props, "lastname")]
      |> Enum.filter(&(&1 not in [nil, ""]))
      |> Enum.join(" ")

    initials(name, Map.get(props, "email"))
  end

  defp selected_initials(_), do: "?"

  defp field_section_title(field) do
    field
    |> to_string()
    |> field_group_labels()
  end

  defp field_label(field) do
    Map.get(field_labels(), to_string(field), humanize_field(field))
  end

  defp field_group_labels(field) do
    Map.get(group_labels(), field, humanize_field(field))
  end

  defp group_labels do
    %{
      "firstname" => "Client name",
      "lastname" => "Client name",
      "phone" => "Contact information",
      "mobilephone" => "Contact information",
      "account_value" => "Account value",
      "savings_rate" => "Retirement savings rate"
    }
  end

  defp field_labels do
    %{
      "firstname" => "Client first name",
      "lastname" => "Client last name",
      "phone" => "Phone number",
      "mobilephone" => "Mobile phone",
      "account_value" => "Account value",
      "savings_rate" => "Savings rate"
    }
  end

  defp update_badge_label(field_updates, field) do
    # Get the section title for this field
    section_title = field_section_title(field)

    # Count how many fields in this section are selected
    selected_count =
      field_updates
      |> Enum.filter(fn update ->
        field_section_title(update.field) == section_title && update.selected
      end)
      |> length()

    case selected_count do
      0 -> "0 updates selected"
      1 -> "1 update selected"
      n -> "#{n} updates selected"
    end
  end

  defp selection_summary(updates) do
    total = length(updates)
    selected = Enum.count(updates, & &1.selected)

    # Count unique objects (field groups)
    objects = updates |> Enum.map(&field_section_title(&1.field)) |> Enum.uniq() |> length()

    cond do
      total == 0 -> "No updates selected"
      true -> "#{objects} objects,#{selected} fields in 2 integrations selected to update"
    end
  end

  defp humanize_field(nil), do: "Field update"

  defp humanize_field(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
