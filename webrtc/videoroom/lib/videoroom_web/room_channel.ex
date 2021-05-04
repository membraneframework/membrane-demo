defmodule VideoRoomWeb.RoomChannel do
  use Phoenix.Channel

  require Logger

  @impl true
  def join("room:" <> room_id, %{"displayName" => name}, socket) do
    {room_id, peer_type} =
      case room_id do
        "screensharing:" <> id ->
          {id, :screensharing}

        ^room_id ->
          {room_id, :participant}
      end

    case VideoRoom.Pipeline.lookup(room_id) do
      nil -> VideoRoom.Pipeline.start(room_id)
      pid -> {:ok, pid}
    end
    |> case do
      {:ok, pipeline} ->
        Process.monitor(pipeline)

        {:ok,
         assign(socket, %{
           room_id: room_id,
           pipeline: pipeline,
           peer_type: peer_type,
           display_name: name
         })}

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
    type = socket.assigns.peer_type

    socket
    |> send_to_pipeline(
      {:new_peer, self(), type, socket.assigns.display_name, socket_ref(socket)}
    )

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

  def handle_in("stop", _msg, socket) do
    socket
    |> send_to_pipeline({:remove_peer, self()})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:signal, {:candidate, candidate, sdp_mline_index}}, socket) do
    push(socket, "candidate", %{
      data: %{"candidate" => candidate, "sdpMLineIndex" => sdp_mline_index}
    })

    {:noreply, socket}
  end

  def handle_info({:signal, {:sdp_offer, sdp}, participants}, socket) do
    participants = Enum.map(participants, &%{"displayName" => &1.display_name, "ids" => &1.ids})

    push(socket, "offer", %{data: %{"type" => "offer", "sdp" => sdp}, participants: participants})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:signal, {:replace_track, old_track_id, new_track_id}}, socket) do
    push(socket, "replaceTrack", %{
      data: %{"oldTrackId" => old_track_id, "newTrackId" => new_track_id}
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:signal, {:display_track, track_id}}, socket) do
    push(socket, "displayTrack", %{data: %{"trackId" => track_id}})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_peer, response, ref}, socket) do
    case response do
      {:ok, max_display_num} ->
        reply(ref, {:ok, %{maxDisplayNum: max_display_num}})

      {:error, _reason} = error ->
        reply(ref, error)
    end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _monitor, reason}, socket) do
    push(socket, "error", %{
      error: "Room stopped working, consider restarting your connection, #{inspect(reason)}"
    })

    {:noreply, socket}
  end

  defp send_to_pipeline(socket, message) do
    socket.assigns.pipeline |> send(message)
  end
end
