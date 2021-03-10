import "../css/app.scss";
//
import "phoenix_html";

import { MembraneWebRTC } from "./membraneWebRTC";
import { Socket } from "phoenix";

function addVideoElement(
  stream: MediaStream,
  _: MediaStreamTrack,
  mute: boolean = false
) {
  let video = <HTMLVideoElement>document.getElementById(stream.id);

  if (!video) {
    video = document.createElement("video");
    video.id = stream.id;
    document.getElementById("videochat")?.appendChild(video);
  }
  video.srcObject = stream;
  video.autoplay = true;
  video.playsInline = true;
  video.muted = mute;
}

function removeVideoElement(stream: MediaStream, _: MediaStreamTrack) {
  if (stream.getTracks().length > 0) {
    return;
  }

  const video = <HTMLVideoElement>document.getElementById(stream.id);
  if (video) {
    video.remove();
  }
}

function setErrorMessage(
  message: string = "Cannot connect to server, refresh the page and try again"
) {
  const control = document.getElementById("control");
  if (control) {
    control.innerHTML = message;
  }
}

const socket = new Socket("/socket");
socket.connect();

const roomEl = document.getElementById("room");
if (roomEl) {
  const roomId = roomEl.dataset.roomId || "lobby";

  new MembraneWebRTC(socket, roomId, {
    onAddTrack: addVideoElement,
    onRemoveTrack: removeVideoElement,
    onConnectionError: setErrorMessage,
  }).start();
} else {
  console.error("room element is missing, cannot join video room");
}
