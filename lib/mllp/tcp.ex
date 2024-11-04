defmodule MLLP.TCPContract do
  @callback setopts(socket :: :gen_tcp.socket(), options :: [:gen_tcp.option()]) ::
              :ok | {:error, :inet.posix()}
  @callback send(socket :: :gen_tcp.socket(), packet :: iodata()) :: :ok | {:error, any}
  @callback recv(socket :: :gen_tcp.socket(), length :: integer()) :: {:ok, any} | {:error, any}
  @callback recv(socket :: :gen_tcp.socket(), length :: integer(), timeout :: integer()) ::
              {:ok, any} | {:error, any}

  @callback connect(
              address :: :inet.socket_address() | :inet.hostname(),
              port :: :inet.port_number(),
              options :: [:gen_tcp.connect_option()],
              timeout :: timeout()
            ) :: {:ok, :gen_tcp.socket()} | {:error, any}

  @callback close(socket :: :gen_tcp.socket()) :: :ok
end

defmodule MLLP.TCP do
  @behaviour MLLP.TCPContract

  defdelegate setopts(socket, opts), to: :inet
  defdelegate send(socket, packet), to: :gen_tcp
  defdelegate recv(socket, length), to: :gen_tcp
  defdelegate recv(socket, length, timeout), to: :gen_tcp
  defdelegate connect(address, port, options, timeout), to: :gen_tcp
  defdelegate close(socket), to: :gen_tcp
  defdelegate shutdown(socket, opts), to: :gen_tcp
end
