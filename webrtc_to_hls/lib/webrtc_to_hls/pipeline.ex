defmodule WebRTCToHLS.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC.{EndpointBin, Track}

  import WebRTCToHLS.Utils

  require Membrane.Logger

  @pipeline_registry WebRTCToHLS.PipelineRegistry

  @spec registry() :: atom()
  def registry(), do: @pipeline_registry

  @spec lookup(pid()) :: GenServer.server() | nil
  def lookup(owner) do
    case Registry.lookup(@pipeline_registry, owner) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @spec start_link(pid) :: GenServer.on_start()
  def start_link(owner) do
    do_start(:start_link, owner)
  end

  @spec start(pid) :: GenServer.on_start()
  def start(owner) do
    do_start(:start, owner)
  end

  defp do_start(func, owner) when func in [:start, :start_link] do
    Membrane.Logger.info(
      "[#{inspect(__MODULE__)}] Starting a new pipeline for owner process: #{inspect(owner)}"
    )

    apply(Membrane.Pipeline, func, [
      __MODULE__,
      [owner],
      [name: {:via, Registry, {@pipeline_registry, owner}}]
    ])
  end

  @impl true
  def handle_init([owner_pid]) do
    Process.monitor(owner_pid)

    play(self())
    {:ok, %{owner: owner_pid}}
  end

  @impl true
  def handle_other(:start, _ctx, %{owner: owner} = state) do
    stream_id = Track.stream_id()
    tracks = [Track.new(:audio, stream_id), Track.new(:video, stream_id)]

    directory =
      self()
      |> pid_hash()
      |> hls_output_path()

    # remove directory if it already exists
    File.rm_rf(directory)
    File.mkdir_p!(directory)

    Membrane.Logger.info(
      "[#{inspect(__MODULE__)}] Created output directory '#{directory}' for owner #{
        inspect(owner)
      }"
    )

    children = %{
      endpoint: %EndpointBin{
        outbound_tracks: [],
        inbound_tracks: tracks
      },
      hls: %Membrane.HTTPAdaptiveStream.Sink{
        manifest_module: Membrane.HTTPAdaptiveStream.HLS,
        target_window_duration: 10 |> Membrane.Time.seconds(),
        target_segment_duration: 10 |> Membrane.Time.seconds(),
        persist?: true,
        storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{directory: directory}
      }
    }

    spec = %ParentSpec{children: children, links: []}
    {{:ok, [spec: spec]}, state}
  end

  @impl true
  def handle_other({:signal, msg}, _ctx, state) do
    {{:ok, forward: {:endpoint, {:signal, msg}}}, state}
  end

  def handle_other(:stop, _ctx, state) do
    Membrane.Pipeline.stop_and_terminate(self())
    {:ok, state}
  end

  @impl true
  def handle_other({:DOWN, _ref, :process, owner, _reason}, _ctx, %{owner: owner} = state) do
    Membrane.Pipeline.stop_and_terminate(self())
    {:ok, state}
  end

  @impl true
  def handle_notification(
        {:new_track, track_id, encoding},
        _endpoint,
        _ctx,
        %{owner: owner} = state
      ) do
    %{children: hls_children, links: hls_links} =
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
              video_cmaf_muxer: Membrane.MP4.CMAF.Muxer
            },
            links: [
              link(:endpoint)
              |> via_out(Pad.ref(:output, track_id))
              |> to(:video_parser)
              |> to(:video_payloader)
              |> to(:video_cmaf_muxer)
              |> via_in(:input)
              |> to(:hls)
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
              link(:endpoint)
              |> via_out(Pad.ref(:output, track_id))
              |> to(:opus_decoder)
              |> to(:aac_encoder)
              |> to(:aac_parser)
              |> to(:audio_payloader)
              |> to(:audio_cmaf_muxer)
              |> via_in(:input)
              |> to(:hls)
            ]
          }
      end

    send(owner, {:hls_path, self() |> pid_hash()})

    spec = %ParentSpec{children: hls_children, links: hls_links}
    {{:ok, spec: spec}, state}
  end

  def handle_notification({:end_of_stream, _pad}, :aac_encoder, _ctx, state) do
    {:ok, state}
  end

  def handle_notification({:cleanup, _}, :hls, _ctx, state) do
    directory =
      self()
      |> pid_hash()
      |> hls_output_path()

    File.rm_rf!(directory)
    {:ok, state}
  end

  def handle_notification({:signal, message}, :endpoint, _ctx, %{owner: owner} = state) do
    send(owner, {:signal, message})
    {:ok, state}
  end

  def handle_notification({:track_playable, _ref}, _el, _ctx, state) do
    {:ok, state}
  end
end
