defmodule VideoRoom.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_videoroom_demo,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {VideoRoom.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # {:membrane_core, "~> 0.6.1"},
      {:membrane_core,
       github: "membraneframework/membrane_core", branch: "develop", override: true},
      {:membrane_webrtc_plugin,
       github: "membraneframework/membrane_webrtc_plugin"},
      {:membrane_element_tee, "~> 0.4.1"},
      {:membrane_element_fake, "~> 0.4.0"},
      {:plug_cowboy, "~> 2.0"},
      {:phoenix, "~> 1.5"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_reload, "~> 1.2"},
      {:poison, "~> 3.1"},
      {:jason, "~> 1.2"}
    ]
  end
end
