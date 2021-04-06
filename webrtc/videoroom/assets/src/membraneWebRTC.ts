import { Channel, Socket } from "phoenix";

import { SCREENSHARING_CONSTRAINTS } from "./consts";

const DEFAULT_ERROR_MESSAGE =
  "Cannot connect to the server, try again by refreshing the page";

declare global {
  interface HTMLCanvasElement {
    captureStream: (frames: number) => MediaStream;
  }

  interface MediaDevices {
    getDisplayMedia: (constraints: MediaStreamConstraints) => MediaStream;
  }
}

export default function createFakeStream(): MediaStream {
  const canvas = document.createElement("canvas") as HTMLCanvasElement;
  const ctx = canvas.getContext("2d");
  if (ctx) {
    ctx.fillStyle = "rgba(0,0,0,0)";
    ctx.fillRect(0, 0, 1, 1);
  }
  // return fake stream with framerate 0 so it won't send any media
  return canvas.captureStream(0);
}

interface OfferData {
  data: RTCSessionDescriptionInit;
}

interface CandidateData {
  data: RTCIceCandidateInit;
}

interface ScreensharingData {
  data: { mid: string; status: "start" | "stop" };
}

interface Callbacks {
  onAddTrack?: (track: MediaStreamTrack, stream: MediaStream) => void;
  onRemoveTrack?: (track: MediaStreamTrack, stream: MediaStream) => void;
  onScreensharingStart?: (stream: MediaStream, isLocal: boolean) => void;
  onScreensharingEnd?: () => void;
  onConnectionError?: (message: string) => void;
}

export class MembraneWebRTC {
  private readonly socket: Socket;
  private _channel?: Channel;
  private channelId: string;

  private localTracks: Set<MediaStreamTrack> = new Set<MediaStreamTrack>();
  private localStream?: MediaStream;
  private remoteStreams: Set<MediaStream> = new Set<MediaStream>();
  private fakeStream: MediaStream;
  private localScreensharingStream?: MediaStream;
  private remoteScreensharingStream?: MediaStream;
  private connection?: RTCPeerConnection;
  private readonly rtc_config: RTCConfiguration = {
    iceServers: [
      {
        urls: "stun:stun.l.google.com:19302",
      },
    ],
  };

  private readonly callbacks: Callbacks;

  private get channel(): Channel {
    if (!this._channel) {
      throw new Error("Phoenix channel is not initialized");
    }
    return this._channel;
  }

  private set channel(ch: Channel) {
    this._channel = ch;
  }

  constructor(
    socket: Socket,
    channelId: string,
    callbacks?: Callbacks,
    config?: RTCConfiguration
  ) {
    this.socket = socket;
    this.callbacks = callbacks || {};
    this.channelId = channelId;
    this.rtc_config = config || this.rtc_config;
    this.fakeStream = createFakeStream();

    const handleError = () => {
      this.callbacks.onConnectionError?.(DEFAULT_ERROR_MESSAGE);
      this.stop();
    };

    socket.onError(handleError);
    socket.onClose(handleError);
  }

  public addTrack = (track: MediaStreamTrack, stream: MediaStream) => {
    if (this.connection) {
      throw new Error(
        "Adding tracks when connection is established is not yet supported"
      );
    }
    this.localTracks.add(track);
    this.localStream = stream;
  };

  public start = () => {
    this.channel = this.socket.channel(this.channelId, {});

    this.channel.on("offer", this.onOffer);
    this.channel.on("candidate", this.onRemoteCandidate);
    this.channel.on("screensharing", this.handleScreensharing);

    this.channel.on("error", (data: any) => {
      this.callbacks.onConnectionError?.(data.error);
      this.stop();
    });

    this.channel
      .join()
      .receive("ok", (_: any) => this.channel.push("start", {}))
      .receive("error", (_: any) =>
        this.callbacks.onConnectionError?.(
          "Unable to connect with backend service"
        )
      );
  };

  public stop = () => {
    this.channel.push("stop", {});
    this.channel.leave();
    this.remoteStreams = new Set<MediaStream>();
    if (this.connection) {
      this.connection.onicecandidate = null;
      this.connection.ontrack = null;
    }
    this.connection = undefined;
  };

  public startScreensharing = async () => {
    try {
      this.localScreensharingStream = await navigator.mediaDevices.getDisplayMedia(
        SCREENSHARING_CONSTRAINTS
      );

      this.channel
        .push("start_screensharing", {})
        .receive("ok", (response) => {
          this.replaceFakeStreamWithScreenSharing();
        })
        .receive("error", (data) => {
          console.error("error while trying to start screensharing", data);
          this.localScreensharingStream?.getTracks().forEach((t) => t.stop());
          this.localScreensharingStream = undefined;
        });
    } catch (error) {
      console.error(error);
    }
  };

  public stopScreensharing = async () => {
    this.localScreensharingStream?.getTracks().forEach((t) => {
      t.stop();
      // on why we dispatch 'ended' manually see: https://stackoverflow.com/questions/55953038/why-is-the-ended-event-not-firing-for-this-mediastreamtrack
      t.dispatchEvent(new Event("ended"));
    });
  };

  private replaceFakeStreamWithScreenSharing = () => {
    const [fakeTrack] = this.fakeStream.getTracks();
    const screenSender = this.connection!.getSenders().find((sender) => {
      return sender?.track?.id === fakeTrack.id;
    });

    if (!screenSender) {
      console.error("Could not find sender track for", fakeTrack);
      this.channel.push("stop_screensharing", {});
      return;
    }

    screenSender.replaceTrack(this.localScreensharingStream?.getTracks()[0]!);

    this.localScreensharingStream!.getTracks().forEach((t) => {
      t.onended = (_) => {
        screenSender.replaceTrack(fakeTrack);
        this.callbacks.onScreensharingEnd?.();
        this.channel.push("stop_screensharing", {});
        this.localScreensharingStream = undefined;
      };
    });

    this.callbacks.onScreensharingStart?.(this.localScreensharingStream!, true);
  };

  private onOffer = async (offer: OfferData) => {
    if (!this.connection) {
      this.connection = new RTCPeerConnection(this.rtc_config);
      this.connection.onicecandidate = this.onLocalCandidate();
      this.connection.ontrack = this.onTrack();
      this.localTracks.forEach((track) =>
        this.connection!.addTrack(track, this.localStream!)
      );

      this.connection.oniceconnectionstatechange = (event) => {
        console.log(
          "Ice connection state:",
          (event.target as RTCPeerConnection).iceConnectionState
        );
        if (
          (event.target as RTCPeerConnection).iceConnectionState === "connected"
        ) {
          this.channel.push("connected", {});
        }
      };
      this.fakeStream
        .getTracks()
        .forEach((track) => this.connection!.addTrack(track, this.fakeStream));
    } else {
      this.connection.createOffer({ iceRestart: true });
    }

    try {
      await this.connection.setRemoteDescription(offer.data);
      const answer = await this.connection.createAnswer();
      await this.connection.setLocalDescription(answer);

      this.channel.push("answer", { data: answer });
    } catch (error) {
      console.error(error);
    }
  };

  private onRemoteCandidate = (candidate: CandidateData) => {
    try {
      const iceCandidate = new RTCIceCandidate(candidate.data);
      if (!this.connection) {
        throw new Error(
          "Received new remote candidate but RTCConnection is undefined"
        );
      }
      this.connection.addIceCandidate(iceCandidate);
    } catch (error) {
      console.error(error);
    }
  };

  private onLocalCandidate = () => {
    return (event: RTCPeerConnectionIceEvent) => {
      if (event.candidate) {
        this.channel.push("candidate", { data: event.candidate });
      }
    };
  };

  private onTrack = () => {
    return (event: RTCTrackEvent) => {
      const [stream] = event.streams;
      this.remoteStreams.add(stream);

      const isScreenSharing =
        event.transceiver.mid?.includes("SCREEN") || false;

      stream.onremovetrack = (event) => {
        const hasTracks = stream.getTracks().length > 0;

        // if screen has no tracks left it is about to be deleted
        if (!hasTracks) {
          stream.onremovetrack = null;
          this.remoteStreams.delete(stream);
        }

        // if stream is an active screensharing and has no tracks trigger screensharing end callback
        if (
          isScreenSharing &&
          !hasTracks &&
          stream === this.remoteScreensharingStream
        ) {
          this.callbacks?.onScreensharingEnd?.();
        }

        // if stream is not a screensharing trigger remove track callback
        if (!isScreenSharing) {
          this.callbacks.onRemoveTrack?.(event.track, stream);
        }
      };

      if (!isScreenSharing) {
        this.callbacks.onAddTrack?.(event.track, stream);
      }
    };
  };

  private handleScreensharing = (screensharing: ScreensharingData) => {
    if (screensharing.data.status === "stop") {
      this.callbacks?.onScreensharingEnd?.();
      this.remoteScreensharingStream = undefined;
      return;
    }

    const transceiver = this.connection!.getTransceivers().find(
      (t) => t.mid === screensharing.data.mid
    );
    if (!transceiver || !transceiver.receiver) return;

    this.remoteStreams.forEach((stream) => {
      if (stream.getTrackById(transceiver.receiver.track.id) !== null) {
        this.remoteScreensharingStream = stream;
      }
    });

    if (this.remoteScreensharingStream) {
      this.callbacks?.onScreensharingStart?.(
        this.remoteScreensharingStream,
        false
      );
    }
  };
}
