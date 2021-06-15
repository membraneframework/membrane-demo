import Config

config :membrane_webrtc_to_hls_demo, WebRTCToHLSWeb.Endpoint,
  url: [host: "localhost"],
  https: [
    port: 8443,
    keyfile: "priv/certs/key.pem",
    certfile: "priv/certs/certificate.pem"
  ],
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ],
  code_reloader: true,
  live_reload: [
    dirs: [
      "priv/static",
      "lib/videoroom_web/controllers",
      "lib/videoroom_web/views",
      "lib/videoroom_web/templates"
    ]
  ]

config :logger, level: :debug
