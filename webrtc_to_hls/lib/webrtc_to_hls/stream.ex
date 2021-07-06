defmodule WebRTCToHLS.Stream do
  @moduledoc false

  use GenServer

  require Membrane.Logger

  def start(channel_pid) do
    GenServer.start(__MODULE__, [channel_pid])
  end

  @impl true
  def init([channel_pid]) do
    Membrane.Logger.info(
      "Spawning stream process for channel: #{inspect(self())} for channel #{inspect(channel_pid)}"
    )

    Process.monitor(channel_pid)

    sfu_options = [
      id: UUID.uuid4(),
      extension_options: [
        vad: false
      ],
      network_options: [
        stun_servers: [
          %{server_addr: "stun.l.google.com", server_port: 19_302}
        ],
        turn_servers: []
      ]
    ]

    {:ok, pid} = WebRTCToHLS.Pipeline.start(sfu_options, [])

    send(pid, {:register, self()})
    {:ok, %{sfu_engine: pid, channel_pid: channel_pid}}
  end

  @impl true
  def handle_info({_sfu_engine, {:sfu_media_event, :broadcast, event}}, state) do
    # just a single channel broadcast?
    send(state.channel_pid, {:media_event, event})
    {:noreply, state}
  end

  @impl true
  def handle_info({_sfu_engine, {:sfu_media_event, to, event}}, state) do
    send(state.channel_pid, {:media_event, event})
    {:noreply, state}
  end

  @impl true
  def handle_info({sfu_engine, {:new_peer, peer_id, _metadata, _track_metadata}}, state) do
    send(sfu_engine, {:accept_new_peer, peer_id})
    {:noreply, state}
  end

  @impl true
  def handle_info({_sfu_engine, {:peer_left, _peer_id}}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:media_event, _from, _event} = msg, state) do
    send(state.sfu_engine, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({_sfu_engine, {:playlist_playable, _playlist_idl} = msg}, state) do
    send(state.channel_pid, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{channel_pid: pid} = state) do
    Membrane.Pipeline.stop_and_terminate(state.sfu_engine)
    {:stop, :normal, state}
  end
end
