import Config

config :membrane_webrtc_to_hls_demo, hls_output_mount_path: "output"

config :phoenix, :json_library, Jason

config :membrane_webrtc_to_hls_demo, WebRTCToHLSWeb.Endpoint,
  pubsub_server: WebRTCToHLS.PubSub,
  https: [
    otp_app: :membrane_webrtc_to_hls_demo,
    cipher_suite: :strong
  ]

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :info],
    # Silence irrelevant warnings caused by resending handshake events
    [module: Membrane.SRTP.Encryptor, function: "handle_event/4", level_lower_than: :error]
  ]

config :logger, :console, metadata: [:room]

import_config("#{config_env()}.exs")
