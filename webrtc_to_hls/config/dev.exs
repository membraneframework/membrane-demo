import Config

config :membrane_webrtc_to_hls_demo, WebRTCToHLSWeb.Endpoint,
  url: [host: "localhost"],
  http: [
    port: 4000
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
