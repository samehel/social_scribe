defmodule SocialScribe.Calendar do
  @moduledoc """
  The Calendar context.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo

  alias SocialScribe.Calendar.CalendarEvent

  @doc """
  Lists all upcoming events for a given user from the local database.
  Shows events with future start times that don't have completed meetings.
  """
  def list_upcoming_events(user) do
    now = DateTime.utc_now()

    from(e in CalendarEvent,
      left_join: m in assoc(e, :meeting),
      where: e.user_id == ^user.id,
      where: e.start_time > ^now,
      where: is_nil(m.id),
      order_by: [asc: e.start_time]
    )
    |> Repo.all()
  end

  @doc """
  Lists calendar events for a user within a specific time range.
  """
  def list_calendar_events_in_range(user_id, start_time, end_time) do
    from(e in CalendarEvent,
      where: e.user_id == ^user_id and e.start_time >= ^start_time and e.start_time <= ^end_time,
      order_by: [asc: e.start_time]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of calendar_events.

  ## Examples

      iex> list_calendar_events()
      [%CalendarEvent{}, ...]

  """
  def list_calendar_events do
    Repo.all(CalendarEvent)
  end

  @doc """
  Gets a single calendar_event.

  Raises `Ecto.NoResultsError` if the Calendar event does not exist.

  ## Examples

      iex> get_calendar_event!(123)
      %CalendarEvent{}

      iex> get_calendar_event!(456)
      ** (Ecto.NoResultsError)

  """
  def get_calendar_event!(id), do: Repo.get!(CalendarEvent, id)

  @doc """
  Gets a calendar event by user_id and google_event_id.
  Returns nil if not found.
  """
  def get_calendar_event_by_google_id(user_id, google_event_id) do
    Repo.get_by(CalendarEvent, user_id: user_id, google_event_id: google_event_id)
  end

  @doc """
  Creates a calendar_event.

  ## Examples

      iex> create_calendar_event(%{field: value})
      {:ok, %CalendarEvent{}}

      iex> create_calendar_event(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_calendar_event(attrs \\ %{}) do
    %CalendarEvent{}
    |> CalendarEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a calendar_event.

  ## Examples

      iex> update_calendar_event(calendar_event, %{field: new_value})
      {:ok, %CalendarEvent{}}

      iex> update_calendar_event(calendar_event, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_calendar_event(%CalendarEvent{} = calendar_event, attrs) do
    calendar_event
    |> CalendarEvent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a calendar_event.

  ## Examples

      iex> delete_calendar_event(calendar_event)
      {:ok, %CalendarEvent{}}

      iex> delete_calendar_event(calendar_event)
      {:error, %Ecto.Changeset{}}

  """
  def delete_calendar_event(%CalendarEvent{} = calendar_event) do
    Repo.delete(calendar_event)
  end

  @doc """
  Deletes a calendar_event with cascade deletion of all related records.
  Deletes in order: meetings -> recall_bots -> calendar_event
  """
  def delete_calendar_event_cascade(%CalendarEvent{} = calendar_event) do
    import Ecto.Query

    Repo.transaction(fn ->
      # Delete meetings that reference this calendar event
      from(m in "meetings", where: m.calendar_event_id == ^calendar_event.id)
      |> Repo.delete_all()

      # Delete recall_bots that reference this calendar event
      from(rb in "recall_bots", where: rb.calendar_event_id == ^calendar_event.id)
      |> Repo.delete_all()

      # Finally delete the calendar event itself
      case Repo.delete(calendar_event) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking calendar_event changes.

  ## Examples

      iex> change_calendar_event(calendar_event)
      %Ecto.Changeset{data: %CalendarEvent{}}

  """
  def change_calendar_event(%CalendarEvent{} = calendar_event, attrs \\ %{}) do
    CalendarEvent.changeset(calendar_event, attrs)
  end

  @doc """
  Creates or updates a calendar event.
  Preserves record_meeting flag and prevents updates to events with completed meetings.

  ## Examples

      iex> create_or_update_calendar_event(%{field: value})
      {:ok, %CalendarEvent{}}

  """
  def create_or_update_calendar_event(attrs \\ %{}) do
    # Check if this event already exists and has a completed meeting
    existing_event =
      case attrs do
        %{user_id: user_id, google_event_id: google_event_id} when not is_nil(user_id) and not is_nil(google_event_id) ->
          Repo.get_by(CalendarEvent, user_id: user_id, google_event_id: google_event_id)
        _ ->
          nil
      end

    # If event has completed meeting, don't update times
    if existing_event && has_completed_meeting?(existing_event) do
      # Return existing event without updating
      {:ok, existing_event}
    else
      on_conflict =
        attrs
        |> Map.delete(:record_meeting)
        |> Map.to_list()

      %CalendarEvent{}
      |> CalendarEvent.changeset(attrs)
      |> Repo.insert(
        on_conflict: [set: on_conflict],
        conflict_target: [:user_id, :google_event_id]
      )
    end
  end

  @doc """
  Checks if a calendar event has an associated meeting that has been recorded.
  """
  def has_completed_meeting?(%CalendarEvent{} = calendar_event) do
    from(m in "meetings",
      where: m.calendar_event_id == ^calendar_event.id and not is_nil(m.recorded_at),
      select: count(m.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end
end
