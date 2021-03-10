defmodule Membrane.Demo.WebRTCToHLS.Router do
  use Plug.Router

  plug(Plug.Static,
    at: "/",
    from: :membrane_webrtc_to_hls_demo
  )

  plug(:match)
  plug(:dispatch)

  get "/" do
    send_file(conn, 200, "priv/static/html/index.html")
  end

  match _ do
    send_resp(conn, 404, "404")
  end
end
