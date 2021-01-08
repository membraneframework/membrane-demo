defmodule Recording.MixProject do
  use Mix.Project

  def project do
    [
      app: :recording_demo,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Membrane.Recording.App, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 0.6.1"},
      {:membrane_file_plugin, "~> 0.5.0"},
      {:membrane_hackney_plugin, "~> 0.4.0"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.6.0"},
      {:membrane_rtp_h264_plugin, "~> 0.4.0"},
      {:membrane_dtls_plugin, "~> 0.1.0"},
      {:membrane_rtp_plugin, "~> 0.5.0"},
      {:ex_libsrtp, "~> 0.1.0"},
      {:membrane_rtp_opus_plugin, "~> 0.2.0"},
      {:membrane_opus_plugin, "~> 0.2.0"},
      {:membrane_webrtc_server, "~> 0.1.0"},
      {:ex_sdp, "~> 0.2.0"},
      {:websockex, "~> 0.4.2"},
      {:poison, "~> 3.1"},
      {:jason, "~> 1.1"},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"}
    ]
  end
end
