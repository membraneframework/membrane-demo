defmodule WebRTCToHLSWeb.Router do
  use WebRTCToHLSWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", WebRTCToHLSWeb do
    pipe_through(:browser)

    get("/", PageController, :index)
    get("/player/:prefix", PageController, :player)
    get("/video/:prefix/:filename", HLSController, :index)
  end
end
