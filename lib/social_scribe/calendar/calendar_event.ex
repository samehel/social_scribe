defmodule SocialScribe.Calendar.CalendarEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_events" do
    field :status, :string
    field :description, :string
    field :location, :string
    field :google_event_id, :string
    field :summary, :string
    field :html_link, :string
    field :hangout_link, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :record_meeting, :boolean, default: false
    field :user_id, :id
    field :user_credential_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(calendar_event, attrs) do
    calendar_event
    |> cast(attrs, [
      :google_event_id,
      :summary,
      :description,
      :location,
      :html_link,
      :hangout_link,
      :status,
      :start_time,
      :end_time,
      :record_meeting,
      :user_id,
      :user_credential_id
    ])
    |> validate_required([
      :google_event_id,
      :summary,
      :html_link,
      :status,
      :start_time,
      :end_time,
      :user_id,
      :user_credential_id
    ])
    |> validate_time_order()
    |> validate_reasonable_duration()
  end

  defp validate_time_order(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(start_time, end_time) != :lt do
      add_error(changeset, :start_time, "must be before end time")
    else
      changeset
    end
  end

  defp validate_reasonable_duration(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time do
      duration_seconds = DateTime.diff(end_time, start_time)
      min_duration = 60  # 1 minute
      max_duration = 86_400  # 24 hours

      cond do
        duration_seconds < min_duration ->
          add_error(changeset, :end_time, "meeting duration must be at least 1 minute")

        duration_seconds > max_duration ->
          add_error(changeset, :end_time, "meeting duration cannot exceed 24 hours")

        true ->
          changeset
      end
    else
      changeset
    end
  end
end
