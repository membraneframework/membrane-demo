defmodule WebRTCToHLSWeb do
  def controller do
    quote do
      use Phoenix.Controller, namespace: WebRTCToHLSWeb
      import Plug.Conn
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/webrtc_to_hls_web/templates",
        pattern: "**/*",
        namespace: WebRTCToHLSWeb

      import WebRTCToHLSWeb.Router.Helpers

      use Phoenix.HTML
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
