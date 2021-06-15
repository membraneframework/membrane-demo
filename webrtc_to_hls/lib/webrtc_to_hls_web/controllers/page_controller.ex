defmodule WebRTCToHLSWeb.PageController do
  use WebRTCToHLSWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def player(conn, %{"prefix" => prefix}) do
    render(conn, "player.html", prefix: prefix)
  end
end
