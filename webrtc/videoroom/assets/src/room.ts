import "../css/app.scss";

import { MEDIA_CONSTRAINTS, LOCAL_PEER_ID } from "./consts";
import {
  addVideoElement,
  getRoomId,
  removeVideoElement,
  setErrorMessage,
  setParticipantsList,
  attachStream,
} from "./room_ui";
import { MembraneWebRTC, Peer, SerializedMediaEvent } from "membrane_sfu";
import { Push, Socket } from "phoenix";
import { parse } from "query-string";

export class Room {
  private peers: Peer[] = [];
  private displayName: string;
  private localStream: MediaStream | undefined;
  private webrtc: MembraneWebRTC;

  private socket;
  private webrtcSocketRefs: string[] = [];
  private webrtcChannel;

  constructor() {
    this.socket = new Socket("/socket");
    this.socket.connect();
    this.displayName = this.parseUrl();
    this.webrtcChannel = this.socket.channel(`room:${getRoomId()}`);

    this.webrtcSocketRefs.push(this.socket.onError(this.leave));
    this.webrtcSocketRefs.push(this.socket.onClose(this.leave));

    this.webrtc = new MembraneWebRTC({
      callbacks: {
        onSendMediaEvent: (mediaEvent: SerializedMediaEvent) => {
          this.webrtcChannel.push("mediaEvent", { data: mediaEvent });
        },
        onTrackAdded: ({ stream, peer, metadata }) => {
          attachStream(stream, peer.id);
        },
        onConnectionError: setErrorMessage,
        onJoined: (peerId, peersInRoom) => {
          this.peers = peersInRoom;
          this.peers.forEach((peer) => {
            addVideoElement(peer.id, peer.metadata.displayName, false);
          });

          this.updateParticipantsList();
        },
        onDenied: (data) => {
          throw `Peer denied.`;
        },

        onPeerJoined: (peer) => {
          this.peers.push(peer);
          this.updateParticipantsList();
          addVideoElement(peer.id, peer.metadata.displayName, false);
        },
        onPeerLeft: (peer) => {
          this.peers = this.peers.filter((p) => p.id !== peer.id);
          removeVideoElement(peer.id);
          this.updateParticipantsList();
        },
      },
    });

    this.webrtcChannel.on("mediaEvent", (event) =>
      this.webrtc.receiveMediaEvent(event.data)
    );
  }

  public init = async () => {
    await this.phoenixChannelPushResult(this.webrtcChannel.join());

    try {
      this.localStream = await navigator.mediaDevices.getUserMedia(
        MEDIA_CONSTRAINTS
      );
    } catch (error) {
      console.error(error);
      setErrorMessage(
        "Failed to setup video room, make sure to grant camera and microphone permissions"
      );
      throw "error";
    }

    this.localStream
      .getTracks()
      .forEach((track) => this.webrtc.addTrack(track, this.localStream!));

    addVideoElement(LOCAL_PEER_ID, "Me", true);
    attachStream(this.localStream, LOCAL_PEER_ID);
  };

  public join = () => {
    this.webrtc.join({ displayName: this.displayName });
  };

  private leave = () => {
    this.webrtc.leave();
    this.webrtcChannel.leave();
    this.socket.off(this.webrtcSocketRefs);
    while (this.webrtcSocketRefs.length > 0) {
      this.webrtcSocketRefs.pop();
    }
  };

  private parseUrl = (): string => {
    const { display_name: displayName } = parse(document.location.search);

    // remove query params without reloading the page
    window.history.replaceState(null, "", window.location.pathname);

    return displayName as string;
  };

  private updateParticipantsList = (): void => {
    const participantsNames = this.peers.map((p) => p.metadata.displayName);

    if (this.displayName) {
      participantsNames.push(this.displayName);
    }

    setParticipantsList(participantsNames);
  };

  private phoenixChannelPushResult = async (push: Push): Promise<any> => {
    return new Promise((resolve, reject) => {
      push
        .receive("ok", (response: any) => resolve(response))
        .receive("error", (response: any) => reject(response));
    });
  };
}
