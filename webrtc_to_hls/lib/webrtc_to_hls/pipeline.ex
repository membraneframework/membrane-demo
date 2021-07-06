defmodule WebRTCToHLS.Pipeline do
  use Membrane.Pipeline

  require Membrane.Logger

  alias Membrane.WebRTC.{Endpoint, EndpointBin, Track}
  alias Membrane.SFU.MediaEvent

  import WebRTCToHLS.Helpers

  @registry_name WebRTCToHLS.Registry

  @type stun_server_t() :: ExLibnice.stun_server()
  @type turn_server_t() :: ExLibnice.relay_info()

  @type extension_options_t() :: [
          vad: boolean()
        ]

  @type network_options_t() :: [
          stun_servers: [stun_server_t()],
          turn_servers: [turn_server_t()],
          dtls_pkey: binary(),
          dtls_cert: binary()
        ]

  @type options_t() :: [
          id: String.t(),
          extension_options: extension_options_t(),
          network_options: network_options_t()
        ]

  @spec start(options :: options_t(), process_options :: GenServer.options()) ::
          GenServer.on_start()
  def start(options, process_options) do
    do_start(:start, options, process_options)
  end

  @spec start_link(options :: options_t(), process_options :: GenServer.options()) ::
          GenServer.on_start()
  def start_link(options, process_options) do
    do_start(:start_link, options, process_options)
  end

  defp do_start(func, options, process_options) when func in [:start, :start_link] do
    id = options[:id] || "#{UUID.uuid4()}"
    options = Keyword.put(options, :id, id)

    Membrane.Logger.info("Starting a new SFU instance with id: #{id}")

    apply(Membrane.Pipeline, func, [
      __MODULE__,
      options,
      process_options
    ])
  end

  @impl true
  def handle_init(options) do
    play(self())

    {{:ok, log_metadata: [sfu: options[:id]]},
     %{
       id: options[:id],
       peers: %{},
       incoming_peers: %{},
       endpoints: %{},
       options: options
     }}
  end

  defp get_registry_name(), do: @registry_name

  @impl true
  def handle_other({:register, pid}, _ctx, state) do
    Registry.register(get_registry_name(), self(), pid)
    {:ok, state}
  end

  @impl true
  def handle_other({:unregister, pid}, _ctx, state) do
    Registry.unregister_match(get_registry_name(), self(), pid)
    {:ok, state}
  end

  @impl true
  def handle_other({:remove_peer, id}, ctx, state) do
    {actions, state} = remove_peer(id, ctx, state)
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:media_event, from, data}, ctx, state) do
    case MediaEvent.deserialize(data) do
      {:ok, event} ->
        {actions, state} = handle_media_event(event, from, ctx, state)
        {{:ok, actions}, state}

      {:error, :invalid_media_event} ->
        Membrane.Logger.warn("Invalid media event #{inspect(data)}")
        {:ok, state}
    end
  end

  defp handle_media_event(%{type: :join, data: data}, peer_id, ctx, state) do
    dispatch({:new_peer, peer_id, data.metadata, data.tracks_metadata}, state)

    receive do
      {:accept_new_peer, ^peer_id} ->
        peer = Map.put(data, :id, peer_id)
        state = put_in(state, [:incoming_peers, peer_id], peer)
        {actions, state} = setup_peer(peer, ctx, state)

        MediaEvent.create_peer_accepted_event(peer_id, Map.delete(state.peers, peer_id))
        |> dispatch(state)

        {actions, state}

      {:accept_new_peer, _other_peer_id} ->
        Membrane.Logger.warn("Unknown peer id passed for acceptance: #{inspect(peer_id)}")
        {[], state}

      {:deny_new_peer, peer_id} ->
        MediaEvent.create_peer_denied_event(peer_id)
        |> dispatch(state)

        {[], state}
    end
  end

  defp handle_media_event(%{type: :sdp_answer} = event, peer_id, ctx, state) do
    actions = [
      forward: {{:endpoint, peer_id}, {:signal, {:sdp_answer, event.data.sdp_answer.sdp}}}
    ]

    {tracks_msgs, state} =
      if Map.has_key?(state.incoming_peers, peer_id) do
        inbound_tracks = Map.values(state.endpoints[peer_id].inbound_tracks)
        {peer, state} = pop_in(state, [:incoming_peers, peer_id])
        peer = Map.delete(peer, :tracks_metadata)
        peer = Map.put(peer, :mid_to_track_metadata, event.data.mid_to_track_metadata)
        state = put_in(state, [:peers, peer_id], peer)
        tracks_msgs = update_track_messages(ctx, inbound_tracks, {:endpoint, peer_id})

        MediaEvent.create_peer_joined_event(
          peer_id,
          state.peers[peer_id].metadata,
          event.data.mid_to_track_metadata
        )
        |> dispatch(state)

        {tracks_msgs, state}
      else
        {[], state}
      end

    {actions ++ tracks_msgs, state}
  end

  defp handle_media_event(%{type: :candidate} = event, peer_id, _ctx, state) do
    actions = [forward: {{:endpoint, peer_id}, {:signal, {:candidate, event.data.candidate}}}]
    {actions, state}
  end

  defp handle_media_event(%{type: :leave}, peer_id, ctx, state) do
    {actions, state} = remove_peer(peer_id, ctx, state)
    {actions, state}
  end

  @impl true
  def handle_notification({:signal, message}, {:endpoint, peer_id}, _ctx, state) do
    MediaEvent.create_signal_event(peer_id, {:signal, message})
    |> dispatch(state)

    {:ok, state}
  end

  @impl true
  def handle_notification({:new_track, track_id, encoding}, endpoint_bin_name, ctx, state) do
    Membrane.Logger.info(
      "New incoming #{encoding} track #{track_id} from #{inspect(endpoint_bin_name)}"
    )

    {:endpoint, endpoint_id} = endpoint_bin_name

    tee = {:tee, {endpoint_id, track_id}}
    fake = {:fake, {endpoint_id, track_id}}

    children = %{
      tee => Membrane.Element.Tee.Master,
      fake => Membrane.Element.Fake.Sink.Buffers
    }

    extensions = setup_extensions(encoding, state[:options][:extension_options])

    links =
      [
        link(endpoint_bin_name)
        |> via_out(Pad.ref(:output, track_id), options: [extensions: extensions])
        |> to(tee)
        |> via_out(:master)
        |> to(fake)
      ] ++
        flat_map_children(ctx, fn
          {:endpoint, other_endpoint_id} = other_endpoint_name ->
            if endpoint_bin_name != other_endpoint_name and
                 state.endpoints[other_endpoint_id].ctx.receive_media do
              [
                link(tee)
                |> via_out(:copy)
                |> via_in(Pad.ref(:input, track_id), options: [encoding: encoding])
                |> to(other_endpoint_name)
              ]
            else
              []
            end

          _child ->
            []
        end)

    %{children: hls_children, links: hls_links} =
      create_hls_links(endpoint_bin_name, track_id, encoding)

    spec = %ParentSpec{
      children: Map.merge(children, hls_children),
      links: links ++ hls_links,
      crash_group: {endpoint_id, :temporary}
    }

    state =
      update_in(
        state,
        [:endpoints, endpoint_id],
        &Endpoint.update_track_encoding(&1, track_id, encoding)
      )

    {{:ok, spec: spec}, state}
  end

  def handle_notification({:vad, val}, {:endpoint, endpoint_id}, _ctx, state) do
    dispatch({:vad_notification, val, endpoint_id}, state)
    {:ok, state}
  end

  def handle_notification({:track_playable, pad_name}, :hls_sink, _ctx, state) do
    # notify about playable just when video becomes available
    if pad_name == :video do
      dispatch({:playlist_playable, self() |> pid_hash()}, state)
    end

    {:ok, state}
  end

  # the peer has left, ignore the notification as the pipeline is closing on its own
  def handle_notification({:end_of_stream, :input}, :aac_encoder, _ctx, state) do
    {:ok, state}
  end

  def handle_notification({:cleanup, fun}, :hls_sink, _ctx, state) do
    fun.()
    {:ok, state}
  end

  defp dispatch(msg, state) do
    Registry.dispatch(get_registry_name(), self(), fn entries ->
      for {_, pid} <- entries, do: send(pid, {self(), msg})
    end)
  end

  defp setup_peer(config, ctx, state) do
    inbound_tracks = create_inbound_tracks(config.relay_audio, config.relay_video)
    outbound_tracks = get_outbound_tracks(state.endpoints, config.receive_media)

    # FIXME `type` field should probably be deleted from Endpoint struct
    endpoint =
      Endpoint.new(config.id, :participant, inbound_tracks, %{receive_media: config.receive_media})

    endpoint_bin_name = {:endpoint, config.id}

    handshake_opts =
      if state.options[:network_options][:dtls_pkey] &&
           state.options[:network_options][:dtls_cert] do
        [
          client_mode: false,
          dtls_srtp: true,
          pkey: state.options.network_options.dtls_pkey,
          cert: state.options.network_options.dtls_cert
        ]
      else
        [
          client_mode: false,
          dtls_srtp: true
        ]
      end

    directory =
      self()
      |> pid_hash()
      |> hls_output_path()

    # remove directory if it already exists
    File.rm_rf(directory)
    File.mkdir_p!(directory)

    children = %{
      endpoint_bin_name => %EndpointBin{
        outbound_tracks: outbound_tracks,
        inbound_tracks: inbound_tracks,
        stun_servers: state.options[:network_options][:stun_servers] || [],
        turn_servers: state.options[:network_options][:turn_servers] || [],
        video_codecs: [
          %ExSDP.Attribute.RTPMapping{payload_type: 96, encoding: "H264", clock_rate: 90_000}
        ],
        use_default_codecs: [:audio],
        handshake_opts: handshake_opts,
        log_metadata: [peer_id: config.id]
      },
      hls_sink: %Membrane.HTTPAdaptiveStream.Sink{
        manifest_module: Membrane.HTTPAdaptiveStream.HLS,
        target_window_duration: 20 |> Membrane.Time.seconds(),
        target_segment_duration: 2 |> Membrane.Time.seconds(),
        persist?: false,
        storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{directory: directory}
      }
    }

    links = create_links(config.receive_media, endpoint_bin_name, ctx, state)

    spec = %ParentSpec{children: children, links: links, crash_group: {config.id, :temporary}}

    state = put_in(state.endpoints[config.id], endpoint)

    {[spec: spec], state}
  end

  defp create_inbound_tracks(relay_audio, relay_video) do
    stream_id = Track.stream_id()
    audio_track = if relay_audio, do: [Track.new(:audio, stream_id)], else: []
    video_track = if relay_video, do: [Track.new(:video, stream_id)], else: []
    audio_track ++ video_track
  end

  defp get_outbound_tracks(endpoints, true) do
    Enum.flat_map(endpoints, fn {_id, endpoint} -> Endpoint.get_tracks(endpoint) end)
  end

  defp get_outbound_tracks(_endpoints, false), do: []

  defp create_links(_receive_media = true, new_endpoint_bin_name, ctx, state) do
    flat_map_children(ctx, fn
      {:tee, {endpoint_id, track_id}} = tee ->
        endpoint = state.endpoints[endpoint_id]
        track = Endpoint.get_track_by_id(endpoint, track_id)

        [
          link(tee)
          |> via_out(:copy)
          |> via_in(Pad.ref(:input, track_id), options: [encoding: track.encoding])
          |> to(new_endpoint_bin_name)
        ]

      _child ->
        []
    end)
  end

  defp create_links(_receive_media = false, _endpoint, _ctx, _state) do
    []
  end

  defp create_hls_links(endpoint_bin_name, track_id, encoding) do
    {:endpoint, endpoint_id} = endpoint_bin_name
    tee_element = {:tee, {endpoint_id, track_id}}

    case encoding do
      :H264 ->
        %{
          children: %{
            video_parser: %Membrane.H264.FFmpeg.Parser{
              framerate: {30, 1},
              alignment: :au,
              attach_nalus?: true
            },
            video_payloader: Membrane.MP4.Payloader.H264,
            video_cmaf_muxer: %Membrane.MP4.CMAF.Muxer{
              segment_duration: 2 |> Membrane.Time.seconds()
            }
          },
          links: [
            link(tee_element)
            |> via_out(:copy)
            |> to(:video_parser)
            |> to(:video_payloader)
            |> to(:video_cmaf_muxer)
            |> via_in(Pad.ref(:input, :video))
            |> to(:hls_sink)
          ]
        }

      :OPUS ->
        %{
          children: %{
            opus_decoder: Membrane.Opus.Decoder,
            aac_encoder: Membrane.AAC.FDK.Encoder,
            aac_parser: %Membrane.AAC.Parser{out_encapsulation: :none},
            audio_payloader: Membrane.MP4.Payloader.AAC,
            audio_cmaf_muxer: Membrane.MP4.CMAF.Muxer
          },
          links: [
            link(tee_element)
            |> via_out(:copy)
            |> to(:opus_decoder)
            |> to(:aac_encoder)
            |> to(:aac_parser)
            |> to(:audio_payloader)
            |> to(:audio_cmaf_muxer)
            |> via_in(Pad.ref(:input, :audio))
            |> to(:hls_sink)
          ]
        }
    end
  end

  defp setup_extensions(encoding, extension_options) do
    if encoding == :OPUS and extension_options[:vad], do: [{:vad, Membrane.RTP.VAD}], else: []
  end

  defp remove_peer(peer_id, ctx, state) do
    case do_remove_peer(peer_id, ctx, state) do
      {:absent, [], state} ->
        Membrane.Logger.info("Peer #{inspect(peer_id)} already removed")
        {[], state}

      {:present, actions, state} ->
        MediaEvent.create_peer_left_event(peer_id)
        |> dispatch(state)

        {actions, state}
    end
  end

  defp do_remove_peer(peer_id, ctx, state) do
    if !Map.has_key?(state.endpoints, peer_id) do
      {:absent, [], state}
    else
      {endpoint, state} = pop_in(state, [:endpoints, peer_id])
      {_peer, state} = pop_in(state, [:peers, peer_id])
      tracks = Enum.map(Endpoint.get_tracks(endpoint), &%Track{&1 | enabled?: false})

      tracks_msgs = update_track_messages(ctx, tracks, {:endpoint, peer_id})

      endpoint_bin = ctx.children[{:endpoint, peer_id}]

      actions =
        if endpoint_bin == nil or endpoint_bin.terminating? do
          []
        else
          children =
            Endpoint.get_tracks(endpoint)
            |> Enum.map(fn track -> track.id end)
            |> Enum.flat_map(&[tee: {peer_id, &1}, fake: {peer_id, &1}])
            |> Enum.filter(&Map.has_key?(ctx.children, &1))

          children = [endpoint: peer_id] ++ children
          [remove_child: children]
        end

      {:present, tracks_msgs ++ actions, state}
    end
  end

  defp update_track_messages(_ctx, [] = _tracks, _endpoint_bin), do: []

  defp update_track_messages(ctx, tracks, endpoint_bin_name) do
    flat_map_children(ctx, fn
      {:endpoint, _endpoint_id} = other_endpoint_bin
      when other_endpoint_bin != endpoint_bin_name ->
        [forward: {other_endpoint_bin, {:add_tracks, tracks}}]

      _child ->
        []
    end)
  end

  defp flat_map_children(ctx, fun) do
    ctx.children |> Map.keys() |> Enum.flat_map(fun)
  end
end
