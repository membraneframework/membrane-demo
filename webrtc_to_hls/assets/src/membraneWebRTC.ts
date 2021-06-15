import { Channel, Socket } from "phoenix";

const RTC_CONFIG: RTCConfiguration = {
  // iceServers: [
  //     YOUR TURN AND STUN SERVERS
  // ]
};

const DEFAULT_ERROR_MESSAGE =
  "Cannot connect to the server, try again by refreshing the page";

interface OfferData {
  data: RTCSessionDescriptionInit;
}

interface CandidateData {
  data: RTCIceCandidateInit;
}

interface Callbacks {
  onConnectionError?: (message: string) => void;
  onAddTrack?: (
    track: MediaStreamTrack,
    stream: MediaStream,
    mute: boolean
  ) => void;
  onRemoveTrack?: (track: MediaStreamTrack, stream: MediaStream) => void;
  onHlsPath: (path: string) => void;
}

export class MembraneWebRTC {
  private readonly socket: Socket;
  private _channel?: Channel;

  private localStream: MediaStream;
  private remoteStreams: Set<MediaStream> = new Set<MediaStream>();
  private connection?: RTCPeerConnection;

  private callbacks?: Callbacks;

  private get channel(): Channel {
    if (!this._channel) {
      throw new Error("Phoenix channel is not initialized");
    }
    return this._channel;
  }

  private set channel(ch: Channel) {
    this._channel = ch;
  }

  constructor(socket: Socket, localStream: MediaStream, callbacks?: Callbacks) {
    this.socket = socket;
    this.callbacks = callbacks;
    this.localStream = localStream;

    const handleError = () => {
      this.callbacks?.onConnectionError?.(DEFAULT_ERROR_MESSAGE);
      this.stop();
    };

    socket.onError(handleError);
    socket.onClose(handleError);
  }

  public start = () => {
    this.channel = this.socket.channel("stream", {});

    this.channel.on("offer", this.onOffer);
    this.channel.on("candidate", this.onRemoteCandidate);
    this.channel.on("hls_path", ({ path }: { path: string }) => {
      this.callbacks?.onHlsPath(path);
    });

    this.channel.on("error", (data: any) => {
      this.callbacks?.onConnectionError?.(data.error);
      this.stop();
    });

    this.channel
      .join()
      .receive("ok", (_: any) => this.channel.push("start", {}))
      .receive("error", (_: any) =>
        this.callbacks?.onConnectionError?.(
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

  private onOffer = async (offer: OfferData) => {
    if (!this.connection) {
      this.connection = new RTCPeerConnection(RTC_CONFIG);
      this.connection.onicecandidate = this.onLocalCandidate();
      this.connection.ontrack = this.onTrack();

      this.localStream
        ?.getTracks()
        .forEach((track) => this.connection?.addTrack(track));
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

      stream.onremovetrack = (event) => {
        if (stream.getTracks().length === 0) {
          stream.onremovetrack = null;
          this.remoteStreams.delete(stream);
        }
        this.callbacks?.onRemoveTrack?.(event.track, stream);
      };

      if (!this.remoteStreams.has(stream)) {
        this.remoteStreams.add(stream);
      }
      this.callbacks?.onAddTrack?.(event.track, stream, false);
    };
  };
}
