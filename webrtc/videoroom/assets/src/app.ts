import "../css/app.scss";

import { addVideoElement, removeVideoElement, setErrorMessage } from "./ui";

import { MembraneWebRTC } from "./membraneWebRTC";
import { Socket } from "phoenix";


interface CapturableMediaElement extends HTMLVideoElement {
  mozCaptureStream: () => MediaStream;
  captureStream: () => MediaStream;
}

const setup = (roomId:String) => {
  const socket = new Socket("/socket");
  socket.connect();
  setTimeout(() => {
    console.log(socket.isConnected())
    const webrtc = new MembraneWebRTC(socket, `room:${roomId}`, {
      onAddTrack: addVideoElement,
      onRemoveTrack: removeVideoElement,
      onConnectionError: setErrorMessage,
    });
    if (window.location.hash == "#test") {
      const test_webrtc = new MembraneWebRTC(socket, `test`, {
        onAddTrack: (track, stream) => {
          const video = <CapturableMediaElement> (document.createElement("video"));
          video.srcObject = stream;
          video.autoplay = true;
          document.getElementById("videochat")?.appendChild(video);
          video.onplay = () => {
            const pipedStream = video.captureStream();
            console.log(pipedStream.getTracks())
            const handleTrack = (track:MediaStreamTrack) => {
              console.log("capture")
              webrtc.addTrack(track, pipedStream);
              if (webrtc.getLocalTracks().size == 2) {
                console.log("start")
                // webrtc.start();
              }
            }
            pipedStream.getTracks().forEach(handleTrack)
            pipedStream.onaddtrack = e => handleTrack(e.track)
          }
          // webrtc.addTrack(track, stream);
          // if (webrtc.getLocalTracks().size == 2) {
          //   console.log("start")
          //   webrtc.start();
          // }
        },
        onRemoveTrack: removeVideoElement,
        onConnectionError: console.error,
      });
      test_webrtc.start();
    } else {
      navigator.mediaDevices.getUserMedia({
        audio: true,
        video: {width: 1280, height: 720}
      }).then((localStream) => {
        localStream
          .getTracks()
          .forEach((track) => {
            console.log(track)
            console.log(localStream)
            addVideoElement(track, localStream, false);
            webrtc.addTrack(track, localStream);
            if (webrtc.getLocalTracks().size == 2) {
              webrtc.start();
            }
          });
      })
    }
  }, 2000);
};

const roomEl = document.getElementById("room");
if (roomEl) {
  setup(roomEl.dataset.roomId || "lobby");
} else {
  console.error("room element is missing, cannot join video room");
}
