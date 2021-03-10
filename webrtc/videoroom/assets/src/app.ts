import "../css/app.scss";

import { addVideoElement, removeVideoElement, setErrorMessage } from "./ui";

import { MembraneWebRTC } from "./membraneWebRTC";
import { Socket } from "phoenix";

const CONSTRAINTS = {
  audio: true,
  video: { width: 1280, height: 720 },
};

const setup = async () => {
  const socket = new Socket("/socket");
  socket.connect();

  const roomEl = document.getElementById("room");
  if (roomEl) {
    try {
      const roomId = roomEl.dataset.roomId || "lobby";

      const localStream = await navigator.mediaDevices.getUserMedia(
        CONSTRAINTS
      );

      const webrtc = new MembraneWebRTC(socket, `room:${roomId}`, {
        onAddTrack: addVideoElement,
        onRemoveTrack: removeVideoElement,
        onConnectionError: setErrorMessage,
      });

      localStream
        .getTracks()
        .forEach(track => {
          webrtc.addTrack(track, localStream);
          addVideoElement(track, localStream, true);
        });

      webrtc.start();
    } catch (error) {
      console.error(error);
      setErrorMessage(
        "Failed to setup video room, make sure to grant camera and microphone permissions"
      );
    }
  } else {
    console.error("room element is missing, cannot join video room");
  }
};

setup();
