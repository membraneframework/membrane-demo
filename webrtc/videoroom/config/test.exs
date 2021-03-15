import Config

config :membrane_videoroom_demo, VideoRoomWeb.Endpoint,
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

config :wallaby,
  driver: Wallaby.Chrome,
  base_url: "https://localhost:8443/",
  max_wait_time: :infinity,
  chromedriver: [
    # headless: true,
    capabilities: %{
      javascriptEnabled: true,
      acceptInsecureCerts: true,
      chromeOptions: %{
        args: [
          # "--remote-debugging-port=9222"
          "--disable-webrtc-hide-local-ips-with-mdns",
          "--disable-web-security",
          "--enable-experimental-web-platform-features",
          "--no-sandbox"
        ]
      }
    }
  ],
  selenium: [
    capabilities: %{
      javascriptEnabled: true,
      browserName: "firefox",
      acceptInsecureCerts: true,
      "moz:firefoxOptions": %{
        args: ["-headless"]
      }
    }
  ]

config :membrane_videoroom_demo, VideoRoomWeb.Endpoint, server: true
