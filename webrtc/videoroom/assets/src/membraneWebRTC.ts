import { Channel, Push, Socket } from "phoenix";

const DEFAULT_ERROR_MESSAGE =
  "Cannot connect to the server, try again by refreshing the page";

const phoenix_channel_push_result = async (push: Push): Promise<any> => {
  return new Promise((resolve, reject) => {
    push
      .receive("ok", (response: any) => resolve(response))
      .receive("error", (response: any) => reject(response));
  });
};

interface OfferData {
  data: RTCSessionDescriptionInit;
}

interface CandidateData {
  data: RTCIceCandidateInit;
}

interface TrackContext {
  track: MediaStreamTrack;
  stream: MediaStream;
  isScreenSharing: boolean;
}

interface Callbacks {
  onAddTrack?: (ctx: TrackContext) => void;
  onRemoveTrack?: (ctx: TrackContext) => void;
  onConnectionError?: (message: string) => void;
  onReplaceStream?: (oldStreamId: String, newStream: MediaStream) => void;
  onDisplayStream?: (stream: MediaStream) => void;
}

interface MembraneWebRTCConfig {
  callbacks?: Callbacks;
  rtcConfig?: RTCConfiguration;
  type?: "participant" | "screensharing";
}

export class MembraneWebRTC {
  private readonly socket: Socket;
  private _channel?: Channel;
  private channelId: string;
  private socketRefs: string[] = [];

  private maxDisplayNum: number = 1;
  private localTracks: Set<MediaStreamTrack> = new Set<MediaStreamTrack>();
  private localStream?: MediaStream;
  private remoteStreams: Set<MediaStream> = new Set<MediaStream>();
  private screensharingStream?: MediaStream;
  private midToStream: Map<String, MediaStream> = new Map();
  private connection?: RTCPeerConnection;
  private readonly rtcConfig: RTCConfiguration = {
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

  constructor(socket: Socket, roomId: string, config: MembraneWebRTCConfig) {
    const { type = "participant", callbacks, rtcConfig } = config;

    this.socket = socket;
    this.channelId =
      type === "participant"
        ? `room:${roomId}`
        : `room:screensharing:${roomId}`;

    this.callbacks = callbacks || {};
    this.rtcConfig = rtcConfig || this.rtcConfig;

    const handleError = () => {
      this.callbacks.onConnectionError?.(DEFAULT_ERROR_MESSAGE);
      this.stop();
    };

    this.socketRefs.push(socket.onError(handleError));
    this.socketRefs.push(socket.onClose(handleError));
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

  public start = async () => {
    this.channel = this.socket.channel(this.channelId, {});

    this.channel.on("offer", this.onOffer);
    this.channel.on("candidate", this.onRemoteCandidate);
    this.channel.on("replaceTrack", (data: any) => {
      const oldTrackId = data.data.oldTrackId;
      const newTrackId = data.data.newTrackId;
      const newStream = this.midToStream.get(newTrackId)!;
      const oldStreamId = this.midToStream.get(oldTrackId)?.id!;
      this.callbacks.onReplaceStream?.(oldStreamId, newStream);
    });
    this.channel.on("displayTrack", (data: any) => {
      const trackId = data.data.trackId;
      const stream = this.midToStream.get(trackId)!;
      this.callbacks.onDisplayStream?.(stream);
    });

    this.channel.on("error", (data: any) => {
      this.callbacks.onConnectionError?.(data.error);
      this.stop();
    });

    await phoenix_channel_push_result(this.channel.join());
    await phoenix_channel_push_result(this.channel.push("start", {})).then(
      (response) => (this.maxDisplayNum = response.maxDisplayNum)
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
    this.localTracks.forEach((t) => t.stop());
    this.connection = undefined;
    this.socket.off(this.socketRefs);
  };

  private onOffer = async (offer: OfferData) => {
    if (!this.connection) {
      this.connection = new RTCPeerConnection(this.rtcConfig);
      this.connection.onicecandidate = this.onLocalCandidate();
      this.connection.ontrack = this.onTrack();
      this.localTracks.forEach((track) =>
        this.connection!.addTrack(track, this.localStream!)
      );
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
      const mid = event.transceiver.mid;
      const isScreenSharing = mid?.includes("SCREEN") || false;

      isScreenSharing
        ? (this.screensharingStream = stream)
        : this.remoteStreams.add(stream);
      this.midToStream.set(mid!, stream);

      stream.onremovetrack = (event) => {
        const hasTracks = stream.getTracks().length > 0;

        if (!hasTracks) {
          isScreenSharing
            ? (this.screensharingStream = undefined)
            : this.remoteStreams.delete(stream);
          this.midToStream.delete(mid!);
          stream.onremovetrack = null;
        }

        this.callbacks.onRemoveTrack?.({
          track: event.track,
          stream,
          isScreenSharing,
        });
      };

      if (this.remoteStreams.size <= this.maxDisplayNum || isScreenSharing) {
        this.callbacks.onAddTrack?.({
          track: event.track,
          stream: stream,
          isScreenSharing,
        });
      }
    };
  };
}
