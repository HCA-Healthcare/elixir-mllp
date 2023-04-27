defmodule MLLP.TCPContract do
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

  @callback is_closed?(socket :: :gen_tcp.socket()) :: boolean()
end

defmodule MLLP.TCP do
  @behaviour MLLP.TCPContract

  defdelegate send(socket, packet), to: :gen_tcp
  defdelegate recv(socket, length), to: :gen_tcp
  defdelegate recv(socket, length, timeout), to: :gen_tcp
  defdelegate connect(address, port, options, timeout), to: :gen_tcp
  defdelegate close(socket), to: :gen_tcp

  @doc """
  Checks if the socket is closed.
  It does so by attempting to read any data from the socket.

  From the [`:gen_tcp` docs](https://www.erlang.org/doc/man/gen_tcp.html#recv-3):

  > Argument Length is only meaningful when the socket is
    in raw mode and denotes the number of bytes to read.
    If Length is 0, all available bytes are returned.
    If Length > 0, exactly Length bytes are returned,
    or an error; possibly discarding less than Length
    bytes of data when the socket is closed from the other
    side.
  """
  @spec is_closed?(socket :: :gen_tcp.socket()) :: boolean()
  def is_closed?(socket) do
    case recv(socket, _length = 0, _timeout = 1) do
      {:error, reason} -> if reason == :timeout, do: false, else: true
      _ -> false
    end
  end
end
