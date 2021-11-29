defmodule MLLP.TLSContract do
  @callback send(socket :: :ssl.sslsocket(), packet :: iodata()) :: :ok | {:error, any}
  @callback recv(socket :: :ssl.sslsocket(), length :: integer()) :: {:ok, any} | {:error, any}
  @callback recv(socket :: :ssl.sslsocket(), length :: integer(), timeout :: integer()) ::
              {:ok, any} | {:error, any}

  @callback connect(
              address :: :inet.socket_address() | :inet.hostname(),
              port :: :inet.port_number(),
              options :: [:ssl.tls_client_option()],
              timeout :: timeout()
            ) :: {:ok, :ssl.sslsocket()} | {:error, any}

  @callback close(socket :: :ssl.sslsocket()) :: :ok
end

defmodule MLLP.TLS do
  @behaviour MLLP.TLSContract

  defdelegate send(socket, packet), to: :ssl
  defdelegate recv(socket, length), to: :ssl
  defdelegate recv(socket, length, timeout), to: :ssl
  defdelegate connect(address, port, options, timeout), to: :ssl
  defdelegate close(socket), to: :ssl
end
