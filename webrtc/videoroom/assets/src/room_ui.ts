export function getRoomId(): string {
  return document.getElementById("room")!.dataset.roomId!;
}

function elementId(peerId: string, type: "video" | "audio" | "feed") {
  return `${type}-${peerId}`;
}

export function attachStream(stream: MediaStream, peerId: string): void {
  const videoId = elementId(peerId, "video");
  const audioId = elementId(peerId, "audio");

  let video = document.getElementById(videoId) as HTMLVideoElement;
  let audio = document.getElementById(audioId) as HTMLAudioElement;

  video.srcObject = stream;
  audio.srcObject = stream;
}

export function addVideoElement(
  peerId: string,
  label: string,
  isLocalVideo: boolean
): void {
  const videoId = elementId(peerId, "video");
  const audioId = elementId(peerId, "audio");

  let video = document.getElementById(videoId) as HTMLVideoElement;
  let audio = document.getElementById(audioId) as HTMLAudioElement;

  if (!video && !audio) {
    const values = setupVideoFeed(peerId, label, isLocalVideo);
    video = values.video;
    audio = values.audio;
  }

  video.id = videoId;
  video.autoplay = true;
  video.playsInline = true;
  video.muted = true;

  audio.id = audioId;
  audio.autoplay = true;
  if (isLocalVideo) {
    audio.muted = true;
  }
}

export function setParticipantsList(participants: Array<string>): void {
  const participantsNamesEl = document.getElementById(
    "participants-list"
  ) as HTMLDivElement;
  participantsNamesEl.innerHTML =
    "<b>Participants</b>: " + participants.join(", ");
}

function resizeVideosGrid() {
  const grid = document.getElementById("videos-grid")!;
  grid.className = `grid-${Math.min(2, grid.children.length)}`;
}

function setupVideoFeed(peerId: string, label: string, isLocalVideo: boolean) {
  const copy = (document.querySelector(
    "#video-feed-template"
  ) as HTMLTemplateElement).content.cloneNode(true) as Element;
  const feed = copy.querySelector("div[class='VideoFeed']") as HTMLDivElement;
  const audio = feed.querySelector("audio") as HTMLAudioElement;
  const video = feed.querySelector("video") as HTMLVideoElement;
  const videoLabel = feed.querySelector(
    "div[class='VideoLabel']"
  ) as HTMLDivElement;

  feed.id = elementId(peerId, "feed");
  videoLabel.innerText = label;

  if (isLocalVideo) {
    video.classList.add("UserOwnVideo");
  }

  const grid = document.querySelector("#videos-grid")!;
  grid.appendChild(feed);
  resizeVideosGrid();

  return { audio, video };
}

export function removeVideoElement(peerId: string): void {
  document.getElementById(elementId(peerId, "feed"))?.remove();
  resizeVideosGrid();
}

export function setErrorMessage(
  message: string = "Cannot connect to server, refresh the page and try again"
): void {
  const errorContainer = document.getElementById("videochat-error");
  if (errorContainer) {
    errorContainer.innerHTML = message;
    errorContainer.style.display = "block";
  }
}
