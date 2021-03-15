defmodule VideoRoom.TestStream do
  use Membrane.Pipeline

  alias Membrane.WebRTC.{EndpointBin, Track}

  @impl true
  def handle_init(_opts) do
    {:ok, %{peer_pid: nil}}
  end

  @impl true
  def handle_other({:new_peer, peer_pid}, _ctx, state) do
    stream_id = Track.stream_id()
    audio = Track.new(:audio, stream_id)
    video = Track.new(:video, stream_id)

    spec = %ParentSpec{
      children: [
        video_src: %Membrane.File.Source{location: "test-video-baseline.h264"},
        video_parser: %Membrane.H264.FFmpeg.Parser{framerate: {30, 1}, alignment: :nal},
        audio_src: %Membrane.File.Source{location: "test-audio.opus"},
        audio_parser: Membrane.Opus.Parser,
        endpoint: %EndpointBin{
          outbound_tracks: [audio, video],
          inbound_tracks: [],
          enforce_realtime?: true
        }
      ],
      links: [
        link(:video_src)
        |> to(:video_parser)
        |> via_in(Pad.ref(:input, video.id), options: [encoding: :H264])
        |> to(:endpoint),
        link(:audio_src)
        |> to(:audio_parser)
        |> via_in(Pad.ref(:input, audio.id), options: [encoding: :OPUS])
        |> to(:endpoint)
      ]
    }

    Process.send_after(self(), :play, 0)
    {{:ok, spec: spec}, %{state | peer_pid: peer_pid}}
  end

  @impl true
  def handle_other(:play, _ctx, state) do
    play(self())
    {:ok, state}
  end

  @impl true
  def handle_other({:signal, message}, _ctx, state) do
    {{:ok, forward: {:endpoint, {:signal, message}}}, state}
  end

  @impl true
  def handle_notification({:signal, message}, :endpoint, _ctx, state) do
    send(state.peer_pid, {:signal, message})
    {:ok, state}
  end
end
