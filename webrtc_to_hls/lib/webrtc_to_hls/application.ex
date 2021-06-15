defmodule WebRTCToHLS.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WebRTCToHLSWeb.Endpoint,
      {Phoenix.PubSub, name: WebRTCToHLS.PubSub},
      {Registry, keys: :unique, name: WebRTCToHLS.Pipeline.registry()},
      WebRTCToHLS.StorageCleanup
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
