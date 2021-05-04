defmodule VideoRoom.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC.{EndpointBin, Track, Endpoint}
  alias VideoRoom.DisplayEngine

  require Membrane.Logger

  @pipeline_registry VideoRoom.PipelineRegistry

  # pipeline has to be started before any peer connects with it
  # therefore there is a possibility that pipeline won't be ever closed
  # (a peer started it but failed to join) so set a timeout at pipeline's start to check
  # if anyone joined the room and close it if no one did
  @empty_room_timeout 5000

  @spec registry() :: atom()
  def registry(), do: @pipeline_registry

  @spec lookup(String.t()) :: GenServer.server() | nil
  def lookup(room_id) do
    case Registry.lookup(@pipeline_registry, room_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  def start_link(room_id) do
    do_start(:start_link, room_id)
  end

  def start(room_id) do
    do_start(:start, room_id)
  end

  defp do_start(func, room_id) when func in [:start, :start_link] do
    Membrane.Logger.info("[VideoRoom.Pipeline] Starting a new pipeline for room: #{room_id}")

    apply(Membrane.Pipeline, func, [
      __MODULE__,
      [room_id],
      [name: {:via, Registry, {@pipeline_registry, room_id}}]
    ])
  end

  @impl true
  def handle_init([room_id]) do
    play(self())

    Process.send_after(self(), :check_if_empty, @empty_room_timeout)

    max_display_num = Application.fetch_env!(:membrane_videoroom_demo, :max_display_num)

    {{:ok, log_metadata: [room: room_id]},
     %{
       room_id: room_id,
       endpoints: %{},
       display_engine: DisplayEngine.new(max_display_num),
       max_display_num: max_display_num,
       active_screensharing: nil
     }}
  end

  @impl true
  def handle_other(
        {:new_peer, peer_pid, :screensharing, ref},
        _ctx,
        %{active_screensharing: screensharing} = state
      )
      when is_pid(screensharing) do
    send(peer_pid, {:new_peer, {:error, "Screensharing is already active"}, ref})
    {:ok, state}
  end

  @impl true
  def handle_other({:new_peer, peer_pid, peer_type, display_name, ref}, ctx, state) do
    send(peer_pid, {:new_peer, {:ok, state.max_display_num}, ref})

    if Map.has_key?(ctx.children, {:endpoint, peer_pid}) do
      Membrane.Logger.warn("Peer already connected, ignoring")
      {:ok, state}
    else
      Membrane.Logger.info("New peer #{inspect(peer_pid)} of type #{inspect(peer_type)}")
      Process.monitor(peer_pid)

      tracks = new_tracks(peer_type)

      endpoint = Endpoint.new(peer_pid, peer_type, tracks, %{display_name: display_name})

      endpoint_bin = {:endpoint, peer_pid}

      display_engine = DisplayEngine.add_new_endpoint(state.display_engine, endpoint)
      state = %{state | display_engine: display_engine}

      stun_servers = Application.fetch_env!(:membrane_videoroom_demo, :stun_servers)
      turn_servers = Application.fetch_env!(:membrane_videoroom_demo, :turn_servers)

      children = %{
        endpoint_bin => %EndpointBin{
          # screensharing type should not receive any streams
          outbound_tracks:
            if(peer_type == :participant, do: get_all_tracks(state.endpoints), else: []),
          inbound_tracks: tracks,
          stun_servers: stun_servers,
          turn_servers: turn_servers,
          handshake_opts: [
            client_mode: false,
            dtls_srtp: true,
            pkey: Application.get_env(:membrane_videoroom_demo, :dtls_pkey),
            cert: Application.get_env(:membrane_videoroom_demo, :dtls_cert)
          ],
          # TODO: change peer_pid to something that will easier identify peer when we introduce
          # participants labelling
          log_metadata: [peer: peer_label(display_name, peer_pid)]
        }
        |> Map.put(:peer_type, peer_type)
      }

      spec = %ParentSpec{children: children}

      state = %{
        stateie
        | active_screensharing:
            if(peer_type == :screensharing, do: peer_pid, else: state.active_screensharing)
      }

      state = put_in(state.endpoints[peer_pid], endpoint)
      {{:ok, [spec: spec]}, state}
    end
  end

  @impl true
  def handle_other({:signal, peer_pid, msg}, _ctx, state) do
    {{:ok, forward: {{:endpoint, peer_pid}, {:signal, msg}}}, state}
  end

  def handle_other({:remove_peer, peer_pid}, ctx, state) do
    case maybe_remove_peer(peer_pid, ctx, state) do
      {:absent, [], state} ->
        Membrane.Logger.info("Peer #{inspect(peer_pid)} already removed")
        {:ok, state}

      {:present, actions, state} ->
        {{:ok, actions}, state}
    end
  end

  def handle_other({:DOWN, _ref, :process, pid, _reason}, ctx, state) do
    {_status, actions, state} = maybe_remove_peer(pid, ctx, state)

    stop_if_empty(state)

    {{:ok, actions}, state}
  end

  def handle_other(:check_if_empty, _ctx, state) do
    stop_if_empty(state)
    {:ok, state}
  end

  @impl true
  def handle_notification({:new_tracks_ids, mid_to_msid}, {:endpoint, endpoint_id}, ctx, state) do
    state =
      state
      |> update_in([:endpoints, endpoint_id], &Endpoint.update_tracks_ids(&1, mid_to_msid))

    endpoints =
      state.display_engine.endpoints
      |> Map.update!(endpoint_id, &Endpoint.update_tracks_ids(&1, mid_to_msid))

    state = %{state | display_engine: %DisplayEngine{state.display_engine | endpoints: endpoints}}

    mid_to_msid =
      Map.get(state, :mid_to_msid, %{})
      |> Map.merge(mid_to_msid)

    state =
      state
      |> Map.put(:mid_to_msid, mid_to_msid)

    child_endpoint_bin = ctx.children[{:endpoint, endpoint_id}][:options]

    inbound_tracks =
      child_endpoint_bin.inbound_tracks
      |> Enum.map(&Map.put(&1, :id, mid_to_msid[&1.mid]))

    links = new_peer_links(child_endpoint_bin.peer_type, {:endpoint, endpoint_id}, ctx, state)

    tracks_msgs =
      flat_map_children(ctx, fn
        {:endpoint, other_peer_pid} = endpoint_bin
        when other_peer_pid != state.active_screensharing and other_peer_pid != endpoint_id ->
          [forward: {endpoint_bin, {:add_tracks, inbound_tracks}}]

        _child ->
          []
      end)

    spec = %ParentSpec{links: links}

    {{:ok, [spec: spec] ++ tracks_msgs}, state}
  end

  @impl true
  def handle_notification({:new_track, track_id, encoding}, endpoint_bin, ctx, state) do
    Membrane.Logger.info("New incoming #{encoding} track #{track_id}")
    {:endpoint, endpoint_id} = endpoint_bin

    endpoint = state.endpoints[endpoint_id]
    display_engine = DisplayEngine.add_new_track(state.display_engine, track_id, endpoint)
    state = %{state | display_engine: display_engine}

    track = Endpoint.get_track_by_id(endpoint, track_id)

    tee = {:tee, {endpoint_id, track_id}}
    fake = {:fake, {endpoint_id, track_id}}

    children = %{
      tee => Membrane.Element.Tee.Parallel,
      fake => Membrane.Element.Fake.Sink.Buffers
    }

    links =
      [
        link(endpoint_bin)
        |> via_out(Pad.ref(:output, track_id))
        |> to(tee)
        |> to(fake)
      ] ++
        flat_map_children(ctx, fn
          {:endpoint, peer_pid} = other_endpoint
          when endpoint_bin != other_endpoint and peer_pid != state.active_screensharing ->
            track_enabled = enable_track?(track, endpoint, peer_pid, state.display_engine)

            [
              link(tee)
              |> via_in(Pad.ref(:input, track_id),
                options: [encoding: encoding, track_enabled: track_enabled]
              )
              |> to(other_endpoint)
            ]

          _child ->
            []
        end)

    spec = %ParentSpec{children: children, links: links}

    state =
      update_in(
        state,
        [:endpoints, endpoint_id],
        &Endpoint.update_track_encoding(&1, track_id, encoding)
      )

    {{:ok, spec: spec}, state}
  end

  def handle_notification(
        {:signal, {:sdp_offer, _} = message},
        {:endpoint, peer_pid},
        _ctx,
        state
      ) do
    participants =
      state.endpoints
      |> Enum.map(fn {_, %Endpoint{inbound_tracks: tracks, ctx: ctx}} ->
        %{display_name: ctx.display_name, ids: Map.keys(tracks)}
      end)

    send(peer_pid, {:signal, message, participants})
    {:ok, state}
  end

  def handle_notification({:signal, message}, {:endpoint, peer_pid}, _ctx, state) do
    send(peer_pid, {:signal, message})
    {:ok, state}
  end

  def handle_notification({:vad, val}, {:endpoint, endpoint_id}, _ctx, state) do
    display_engine = state.display_engine
    {actions, display_engine} = DisplayEngine.vad_notification(display_engine, val, endpoint_id)
    {{:ok, actions}, %{state | display_engine: display_engine}}
  end

  defp maybe_remove_peer(peer_pid, ctx, state) do
    endpoint = ctx.children[{:endpoint, peer_pid}]

    if endpoint == nil or endpoint.terminating? do
      {:absent, [], state}
    else
      {endpoint, state} = pop_in(state, [:endpoints, peer_pid])
      {actions, display_engine} = DisplayEngine.remove_endpoint(state.display_engine, endpoint)
      state = %{state | display_engine: display_engine}
      tracks = Enum.map(Endpoint.get_tracks(endpoint), &%Track{&1 | enabled?: false})

      children =
        Endpoint.get_tracks(endpoint)
        |> Enum.map(fn track -> track.id end)
        |> Enum.flat_map(&[tee: {peer_pid, &1}, fake: {peer_pid, &1}])
        |> Enum.filter(&Map.has_key?(ctx.children, &1))

      children = [endpoint: peer_pid] ++ children

      tracks_msgs =
        flat_map_children(ctx, fn
          {:endpoint, id} when id != peer_pid ->
            [forward: {{:endpoint, id}, {:add_tracks, tracks}}]

          _child ->
            []
        end)

      state =
        if state.active_screensharing == peer_pid do
          %{state | active_screensharing: nil}
        else
          state
        end

      {:present, [remove_child: children] ++ tracks_msgs ++ actions, state}
    end
  end

  defp stop_if_empty(state) do
    if state.endpoints == %{} do
      Membrane.Logger.info("Room '#{state.room_id}' is empty, stopping pipeline")
      Membrane.Pipeline.stop_and_terminate(self())
    end
  end

  defp flat_map_children(ctx, fun) do
    ctx.children |> Map.keys() |> Enum.flat_map(fun)
  end

  defp new_tracks(:participant) do
    stream_id = Track.stream_id()
    [Track.new(:audio, stream_id), Track.new(:video, stream_id)]
  end

  defp new_tracks(:screensharing) do
    screensharing_id = "SCREEN:#{Track.stream_id()}" |> String.slice(0, 16)
    [Track.new(:video, Track.stream_id(), id: screensharing_id)]
  end

  defp new_peer_links(:participant, {:endpoint, new_endpoint_id} = new_endpoint_bin, ctx, state) do
    flat_map_children(ctx, fn
      {:tee, {endpoint_id, track_id}} = tee when endpoint_id != new_endpoint_id ->
        endpoint = state.endpoints[endpoint_id]
        track = Endpoint.get_track_by_id(endpoint, track_id)
        track_enabled = enable_track?(track, endpoint, new_endpoint_id, state.display_engine)

        [
          link(tee)
          |> via_in(Pad.ref(:input, track_id),
            options: [encoding: track.encoding, track_enabled: track_enabled]
          )
          |> to(new_endpoint_bin)
        ]

      _child ->
        []
    end)
  end

  defp new_peer_links(:screensharing, _endpoint, _ctx, _state) do
    []
  end

  defp get_all_tracks(endpoints),
    do: Enum.flat_map(endpoints, fn {_id, endpoint} -> Endpoint.get_tracks(endpoint) end)

  defp enable_track?(track, endpoint, target_endpoint_id, display_engine) do
    # checks if `track` from `endpoint` should be displayed on endpoint with id `target_endpoint_id`
    cond do
      endpoint.type == :screensharing -> true
      track.type == :audio -> true
      true -> DisplayEngine.display?(display_engine, target_endpoint_id, endpoint.id)
    end
  end

  defp peer_label(name, pid) do
    String.slice(name, 0..min(20, String.length(name))) <> ":" <> "#{inspect(pid)}"
  end
end
