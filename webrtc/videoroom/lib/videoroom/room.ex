defmodule Membrane.Room do
  @moduledoc false

  use GenServer

  require Membrane.Logger

  def start(opts) do
    GenServer.start(__MODULE__, [], opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def add_peer_channel(room, peer_channel_pid, peer_id) do
    GenServer.call(room, {:add_peer_channel, peer_channel_pid, peer_id})
  end

  @impl true
  def init(opts) do
    Membrane.Logger.info("Spawning room proces: #{inspect(self())}")

    sfu_options = [
      id: opts[:room_id],
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

    {:ok, pid} = Membrane.SFU.start(sfu_options, [])
    send(pid, {:register, self()})
    {:ok, %{sfu_engine: pid, peer_channels: %{}}}
  end

  @impl true
  def handle_call({:add_peer_channel, peer_channel_pid, peer_pid}, _from, state) do
    state = put_in(state, [:peer_channels, peer_pid], peer_channel_pid)
    Process.monitor(peer_channel_pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({_sfu_engine, {:sfu_media_event, :broadcast, event}}, state) do
    for {_peer_id, pid} <- state.peer_channels, do: send(pid, {:media_event, event})
    {:noreply, state}
  end

  @impl true
  def handle_info({_sfu_engine, {:sfu_media_event, to, event}}, state) do
    send(state.peer_channels[to], {:media_event, event})
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
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {peer_id, _peer_channel_id} =
      state.peer_channels
      |> Enum.find(fn {_peer_id, peer_channel_pid} -> peer_channel_pid == pid end)

    send(state.sfu_engine, {:remove_peer, peer_id})
    {_elem, state} = pop_in(state, [:peer_channels, peer_id])
    {:noreply, state}
  end
end
