export function addVideoElement(
  _: MediaStreamTrack,
  stream: MediaStream,
  mute: boolean = false
) {
  let video = <HTMLVideoElement>document.getElementById(stream.id);
  console.log(stream.id)

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

export function removeVideoElement(_: MediaStreamTrack, stream: MediaStream) {
  if (stream.getTracks().length > 0) {
    return;
  }

  const video = <HTMLVideoElement>document.getElementById(stream.id);
  if (video) {
    video.remove();
  }
}

export function setErrorMessage(
  message: string = "Cannot connect to server, refresh the page and try again"
) {
  const control = document.getElementById("control");
  if (control) {
    control.innerHTML = message;
  }
}
