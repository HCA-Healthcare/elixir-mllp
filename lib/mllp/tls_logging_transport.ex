defmodule MLLP.TLS.HandshakeLoggingTransport do
  @behaviour :ranch_transport

  import MLLP.Utils

  @impl true
  defdelegate name(), to: :ranch_ssl

  @impl true
  defdelegate secure(), to: :ranch_ssl

  @impl true
  defdelegate messages(), to: :ranch_ssl

  @impl true
  defdelegate listen(opts), to: :ranch_ssl

  defdelegate disallowed_listen_options(), to: :ranch_ssl

  @impl true
  defdelegate accept(socket, timeout), to: :ranch_ssl
  defdelegate accept_ack(socket, timeout), to: :ranch_ssl

  @impl true
  defdelegate connect(string, port_number, opts), to: :ranch_ssl

  @impl true
  defdelegate connect(string, port_number, opts, timeout), to: :ranch_ssl

  @impl true
  defdelegate recv(socket, length, timeout), to: :ranch_ssl

  @impl true
  defdelegate recv_proxy_header(socket, timeout), to: :ranch_ssl

  @impl true
  defdelegate send(socket, data), to: :ranch_ssl

  @impl true
  defdelegate sendfile(socket, file), to: :ranch_ssl

  @impl true
  defdelegate sendfile(socket, file, offset, bytes), to: :ranch_ssl

  @impl true
  defdelegate sendfile(socket, file, offset, bytes, opts), to: :ranch_ssl

  @impl true
  defdelegate setopts(socket, opts), to: :ranch_ssl

  @impl true
  defdelegate getopts(socket, opts), to: :ranch_ssl

  @impl true
  defdelegate getstat(socket), to: :ranch_ssl

  @impl true
  defdelegate getstat(socket, opt_names), to: :ranch_ssl

  @impl true
  defdelegate controlling_process(socket, pid), to: :ranch_ssl

  @impl true
  defdelegate peername(socket), to: :ranch_ssl

  @impl true
  defdelegate sockname(socket), to: :ranch_ssl

  @impl true
  defdelegate shutdown(socket, how), to: :ranch_ssl

  @impl true
  defdelegate close(socket), to: :ranch_ssl

  @impl true
  def handshake(socket, opts, timeout) do
    peer_data =
      case peername(socket) do
        {:ok, {ip, port}} ->
          {ip, port}

        {:error, peername_error} ->
          {nil, peername_error}
      end

    case :ssl.handshake(socket, opts, timeout) do
      {:ok, new_socket} ->
        {:ok, new_socket}

      {:error, _} = handshake_error ->
        log_peer(peer_data)
        handshake_error
    end
  end

  defp log_peer({nil, peername_error}) do
    log(:error, "Handshake failure; peer is undetected (#{inspect(peername_error)})")
  end

  defp log_peer({ip, port}) do
    log(:error, "Handshake failure on connection attempt from #{inspect(ip)}:#{inspect(port)}")
  end
end
