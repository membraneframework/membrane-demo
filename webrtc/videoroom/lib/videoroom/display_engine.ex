defmodule VideoRoom.DisplayEngine do
  @moduledoc """
  This module manages endpoints to always show only those video tiles that are currently "speaking".

  It returns actions that enables or disables tracks according to their speech activity events.
  It allows for displaying constant number of video tiles.
  Tiles that are considered to "speaking" will replace tiles that are considered to "silence". If no one is currently
  speaking or there is not enough speaking endpoints there will also be shown endpoints with silence status.
  """

  alias VideoRoom.DisplayManager
  alias Membrane.WebRTC.{Track, Endpoint}

  @opaque t() :: %__MODULE__{
            endpoints: %{},
            display_managers: %{}
          }
  @enforce_keys [:max_display_num, :endpoints, :display_managers]
  defstruct @enforce_keys

  @doc """
  Returns new DisplayEngine state that should be passed to subsequent functions.

  `max_display_num` is a maximal number of streams that should be displayed on peer.
  """
  @spec new(max_display_num :: non_neg_integer()) :: t()
  def new(max_display_num) do
    %__MODULE__{
      max_display_num: max_display_num,
      endpoints: %{},
      display_managers: %{}
    }
  end

  @doc """
  Adds a new endpoint to monitor.

  If other endpoints are going to send video tracks of endpoint `endpoint` then this function should be called.
  Should be paired with `remove_endpoint/2`.
  """
  @spec add_new_endpoint(state :: t(), endpoint :: Endpoint.t()) :: t()
  def add_new_endpoint(state, %Endpoint{type: :screensharing}), do: state

  def add_new_endpoint(state, endpoint) do
    display_manager = DisplayManager.new(state.max_display_num)
    display_manager = setup_display_manager(display_manager, state.endpoints)
    state = put_in(state.display_managers[endpoint.id], display_manager)
    put_in(state.endpoints[endpoint.id], endpoint)
  end

  @doc """
  Adds a new track that will be sent by other endpoints to the peer.
  """
  @spec add_new_track(state :: t(), track_id :: Track.id(), endpoint :: Endpoint.t()) :: t()
  def add_new_track(state, track_id, endpoint) do
    track = Endpoint.get_track_by_id(endpoint, track_id)
    display_managers = add_to_display_managers(track, endpoint, state.display_managers)
    %{state | display_managers: display_managers}
  end

  @doc """
  Updates voice activity status.

  This function should be called each time endpoint with id `endpoint_id` is changing its voice activity state.
  It returns actions that will enable or disable proper tracks in proper endpoints according to a new status of
  voice activity for `endpoint_id`.
  """
  @spec vad_notification(state :: t(), vad :: boolean(), endpoint_id :: Endpoint.id()) ::
          {actions :: [], state :: t()}
  def vad_notification(state, vad, endpoint_id) do
    {actions, display_managers} =
      state.display_managers
      |> Map.delete(endpoint_id)
      |> Enum.flat_map_reduce(state.display_managers, fn
        {id, display_manager}, display_managers ->
          case DisplayManager.update(display_manager, endpoint_id, vad) do
            {:ok, display_manager} ->
              {[], Map.put(display_managers, id, display_manager)}

            {{:replace, old_id, new_id}, display_manager} ->
              old_track_id =
                Endpoint.get_video_tracks(state.endpoints[old_id])
                |> List.first()
                |> case do
                  %Track{id: id} -> id
                end

              new_track_id =
                Endpoint.get_video_tracks(state.endpoints[new_id])
                |> List.first()
                |> case do
                  %Track{id: id} -> id
                end

              actions = [
                {:forward, {{:endpoint, id}, {:disable_track, old_track_id}}},
                {:forward, {{:endpoint, id}, {:enable_track, new_track_id}}}
              ]

              send(id, {:signal, {:replace_track, old_track_id, new_track_id}})
              {actions, Map.put(display_managers, id, display_manager)}
          end
      end)

    state = %{state | display_managers: display_managers}
    {actions, state}
  end

  @doc """
  Returns information if video track of endpoint with id `endpoint_id2` should be displayed on endpoint with id
  `endpoint_id1` i.e. if `endpoint_id1` has free space for video track.
  """
  @spec display?(state :: t(), endpoint_id1 :: Endpoint.id(), endpoint_id2 :: Endpoint.id()) ::
          boolean()
  def display?(state, endpoint_id1, endpoint_id2),
    do: DisplayManager.display?(state.display_managers[endpoint_id1], endpoint_id2)

  @doc """
  Removes endpoint with id `endpoint_id`.

  Should be paired with `add_new_endpoint/2`.
  """
  @spec remove_endpoint(state :: t(), endpoint :: Endpoint.t()) :: {actions :: [], state :: t()}
  def remove_endpoint(state, %Endpoint{type: :screensharing}), do: {[], state}

  def remove_endpoint(state, endpoint) do
    endpoint_id = endpoint.id
    {_display_manager, state} = pop_in(state.display_managers[endpoint_id])
    {_endpoint, state} = pop_in(state.endpoints[endpoint_id])

    {actions, display_managers} =
      cleanup_display_managers(state.display_managers, endpoint_id, state.endpoints)

    {actions, %{state | display_managers: display_managers}}
  end

  defp add_to_display_managers(_track, %Endpoint{type: :screensharing}, display_managers),
    do: display_managers

  defp add_to_display_managers(%Track{type: :audio}, _endpoint, display_managers),
    do: display_managers

  defp add_to_display_managers(_track, %Endpoint{id: id}, display_managers) do
    Map.new(display_managers, fn
      {endpoint_id, display_manager} when endpoint_id != id ->
        {endpoint_id, DisplayManager.add(display_manager, id)}

      {endpoint_id, display_manager} ->
        {endpoint_id, display_manager}
    end)
  end

  defp setup_display_manager(display_manager, endpoints) do
    Enum.reduce(endpoints, display_manager, fn
      {id, %Endpoint{type: :participant}}, display_manager ->
        DisplayManager.add(display_manager, id)

      _, display_manager ->
        display_manager
    end)
  end

  defp cleanup_display_managers(display_managers, endpoint_id, endpoints) do
    Enum.flat_map_reduce(display_managers, display_managers, fn
      {id, display_manager}, display_managers ->
        case DisplayManager.remove(display_manager, endpoint_id) do
          {:ok, display_manager} ->
            {[], Map.put(display_managers, id, display_manager)}

          {{:replace, _old_id, new_id}, display_manager} ->
            new_track_id =
              Endpoint.get_video_tracks(endpoints[new_id])
              |> List.first()
              |> (fn %Track{id: id} -> id end).()

            actions = [{:forward, {{:endpoint, id}, {:enable_track, new_track_id}}}]

            send(id, {:signal, {:display_track, new_track_id}})
            {actions, Map.put(display_managers, id, display_manager)}
        end
    end)
  end
end
