import Config

config :membrane_videoroom_demo, VideoRoomWeb.Endpoint, [
  {:url, [host: "localhost"]},
  {:http, [otp_app: :membrane_videoroom_demo, port: 4000]}
]
