defmodule WebRTCToHLSWeb.StreamChannel do
  use Phoenix.Channel

  require Logger

  alias WebRTCToHLS.Stream

  @impl true
  def join("stream", _params, socket) do
    case Stream.start(self()) do
      {:ok, stream} ->
        peer_id = UUID.uuid4()
        Process.monitor(stream)
        {:ok, assign(socket, %{stream: stream, peer_id: peer_id})}

      {:error, reason} ->
        Logger.error("""
        Failed to start stream.
        Reason: #{inspect(reason)}
        """)

        {:error, %{reason: "failed to start room"}}
    end
  end

  @impl true
  def handle_in("mediaEvent", %{"data" => event}, socket) do
    send(socket.assigns.stream, {:media_event, socket.assigns.peer_id, event})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_event, event}, socket) do
    push(socket, "mediaEvent", %{data: event})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:playlist_playable, playlist_id}, socket) do
    push(socket, "playlistPlayable", %{playlistId: playlist_id})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, stream, reason}, %{stream: stream} = state) do
    {:stop, reason, state}
  end
end
