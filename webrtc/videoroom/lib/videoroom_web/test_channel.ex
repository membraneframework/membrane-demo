defmodule VideoRoomWeb.TestChannel do
  use Phoenix.Channel

  require Logger

  @impl true
  def join("test", _message, socket) do
    {:ok, pipeline} = VideoRoom.TestStream.start_link()
    {:ok, assign(socket, %{pipeline: pipeline})}
  end

  @impl true
  def handle_in("start", _msg, socket) do
    IO.inspect(:start)

    socket
    |> send_to_pipeline({:new_peer, self()})

    {:noreply, socket}
  end

  @impl true
  def handle_in("answer", %{"data" => %{"sdp" => sdp}}, socket) do
    socket
    |> send_to_pipeline({:signal, {:sdp_answer, sdp}})

    {:noreply, socket}
  end

  @impl true
  def handle_in("candidate", %{"data" => %{"candidate" => candidate}}, socket) do
    socket
    |> send_to_pipeline({:signal, {:candidate, candidate}})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:signal, {:candidate, candidate, sdp_mline_index}}, socket) do
    push(socket, "candidate", %{
      data: %{"candidate" => candidate, "sdpMLineIndex" => sdp_mline_index}
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:signal, {:sdp_offer, sdp}}, socket) do
    push(socket, "offer", %{data: %{"type" => "offer", "sdp" => sdp}})
    {:noreply, socket}
  end

  defp send_to_pipeline(socket, message) do
    socket.assigns.pipeline |> send(message)
  end
end
