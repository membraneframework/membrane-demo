import Config

defmodule ConfigParser do
  def parse_stun_servers(""), do: []

  def parse_stun_servers(servers) do
    servers
    |> String.split(",")
    |> Enum.map(fn server ->
      with [addr, port] <- String.split(server, ":"),
           {port, ""} <- Integer.parse(port) do
        %{server_addr: parse_addr(addr), server_port: port}
      else
        _ -> raise("Bad STUN server format. Expected addr:port, got: #{inspect(server)}")
      end
    end)
  end

  def parse_turn_servers(""), do: []

  def parse_turn_servers(servers) do
    servers
    |> String.split(",")
    |> Enum.map(fn server ->
      with [addr, port, username, password, proto] when proto in ["udp", "tcp", "tls"] <-
             String.split(server, ":"),
           {port, ""} <- Integer.parse(port) do
        %{
          server_addr: parse_addr(addr),
          server_port: port,
          username: username,
          password: password,
          proto: String.to_atom(proto)
        }
      else
        _ ->
          raise("""
          "Bad TURN server format. Expected addr:port:username:password:proto, got: \
          #{inspect(server)}
          """)
      end
    end)
  end

  def parse_addr(addr) do
    case :inet.parse_address(String.to_charlist(addr)) do
      {:ok, ip} -> ip
      # FQDN?
      {:error, :einval} -> addr
    end
  end
end

if config_env() == :prod do
  config :membrane_webrtc_to_hls_demo, WebRTCToHLSWeb.Endpoint,
    url: [host: System.fetch_env!("HOST")],
    http: [
      port: System.fetch_env!("PORT") |> String.to_integer()
    ]
end

config :membrane_webrtc_to_hls_demo,
  stun_servers:
    System.get_env("STUN_SERVERS", "64.233.163.127:19302") |> ConfigParser.parse_stun_servers(),
  turn_servers: System.get_env("TURN_SERVERS", "") |> ConfigParser.parse_turn_servers()
