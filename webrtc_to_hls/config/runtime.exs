import Config

if config_env() == :prod do
  config :membrane_webrtc_to_hls_demo, WebRTCToHLSWeb.Endpoint,
    url: [host: System.fetch_env!("HOST")],
    https: [
      port: System.fetch_env!("PORT") |> String.to_integer(),
      keyfile: System.fetch_env!("KEY_FILE_PATH"),
      certfile: System.fetch_env!("CERT_FILE_PATH")
    ]
end
