defmodule VideoRoomWeb.RoomChannel do
  use Phoenix.Channel

  require Logger

  intercept(["screensharing"])

  @impl true
  def join("room:" <> room_id, _message, socket) do
    case VideoRoom.Pipeline.lookup(room_id) do
      nil -> VideoRoom.Pipeline.start(room_id)
      pid -> {:ok, pid}
    end
    |> case do
      {:ok, pipeline} ->
        Process.monitor(pipeline)
        {:ok, assign(socket, %{room_id: room_id, pipeline: pipeline, connected: false})}

      {:error, reason} ->
        Logger.error("""
        Failed to start pipeline
        Room: #{inspect(room_id)}
        Reason: #{inspect(reason)}
        """)

        {:error, %{reason: "failed to start room"}}
    end
  end

  @impl true
  def handle_in("start", _msg, socket) do
    socket
    |> send_to_pipeline({:new_peer, self()})

    {:noreply, socket}
  end

  def handle_in("answer", %{"data" => %{"sdp" => sdp}}, socket) do
    socket
    |> send_to_pipeline({:signal, self(), {:sdp_answer, sdp}})

    {:noreply, socket}
  end

  def handle_in("candidate", %{"data" => %{"candidate" => candidate}}, socket) do
    socket
    |> send_to_pipeline({:signal, self(), {:candidate, candidate}})

    {:noreply, socket}
  end

  # we need one-shot message from peer that he is connected
  # so we can send him current screensharing `mid` information
  #
  # as peer can get connected several times (after each renegotiation)
  # respond just to the first one
  def handle_in("connected", _, socket) do
    if not socket.assigns.connected do
      socket |> send_to_pipeline({:connected, self()})
    end

    {:noreply, socket}
  end

  def handle_in("start_screensharing", _, socket) do
    socket
    |> send_to_pipeline({:start_screensharing, self(), socket_ref(socket)})

    {:noreply, socket}
  end

  def handle_in("stop_screensharing", _, socket) do
    socket
    |> send_to_pipeline({:stop_screensharing, self(), socket_ref(socket)})

    {:noreply, socket}
  end

  def handle_in("stop", _msg, socket) do
    socket
    |> send_to_pipeline({:remove_peer, self()})

    {:noreply, socket}
  end

  @impl true
  def handle_out("screensharing", %{mid: mid, status: status}, socket)
      when socket.assigns.connected do
    push_screensharing(mid, status, socket)
    {:noreply, socket}
  end

  def handle_out("screensharing", msg, socket) do
    """
    #{inspect(__MODULE__)} Received screensharing event on a socket
    that has not yet acknowledged connected status, ignoring: #{inspect(msg)}"
    """
    |> Logger.warn()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:signal, {:candidate, candidate, sdp_mline_index}}, socket) do
    push(socket, "candidate", %{
      data: %{"candidate" => candidate, "sdpMLineIndex" => sdp_mline_index}
    })

    {:noreply, socket}
  end

  def handle_info({:signal, {:sdp_offer, sdp}}, socket) do
    push(socket, "offer", %{data: %{"type" => "offer", "sdp" => sdp}})
    {:noreply, socket}
  end

  def handle_info({:start_screensharing, :already_active, ref}, socket) do
    reply(ref, {:error, %{"reason" => "Someone is already sharing screen"}})
    {:noreply, socket}
  end

  def handle_info({:start_screensharing, mid, ref}, socket) do
    reply(ref, {:ok, %{}})
    broadcast_from(socket, "screensharing", %{mid: mid, status: "start"})
    {:noreply, socket}
  end

  def handle_info({:stop_screensharing, mid, _ref}, socket) do
    broadcast_from(socket, "screensharing", %{mid: mid, status: "stop"})
    {:noreply, socket}
  end

  def handle_info({:connected, payload}, socket) do
    if Map.has_key?(payload, :active_screensharing) do
      push_screensharing(payload.active_screensharing, "start", socket)
    end

    {:noreply, assign(socket, :connected, true)}
  end

  def handle_info({:DOWN, _ref, :process, _monitor, reason}, socket) do
    push(socket, "error", %{
      error: "Room stopped working, consider restarting your connection, #{inspect(reason)}"
    })

    {:noreply, socket}
  end

  def push_screensharing(mid, status, socket) do
    push(socket, "screensharing", %{data: %{mid: mid, status: status}})
  end

  defp send_to_pipeline(socket, message) do
    socket.assigns.pipeline |> send(message)
  end
end
