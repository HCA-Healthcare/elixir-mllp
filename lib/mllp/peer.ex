defmodule MLLP.Peer do
  use OK.Pipe
  require Logger

  @type t :: %{
          :transport => :ranch_tcp | :ranch_ssl,
          :socket => :ranch_transport.socket(),
          :client_info => {:inet.ip_address(), :inet.port_number()},
          optional(:cert) => binary() | :undefined | nil
        }

  @type error_type ::
          :client_ip_not_allowed
          | :no_peercert
          | :fail_to_verify_client_cert
          | :cert_is_expired

  @spec validate(t(), Keyword.t()) :: {:ok, :success} | {:error, error_type()}

  def validate(peer, options) do
    allowed_clients = Keyword.get(options, :allowed_clients, [])
    verify_peer = Keyword.get(options, :verify_peer, false)

    if verify_peer do
      peer
      |> get_peercert()
      ~>> verify_host_name(allowed_clients)
    else
      validate_client_ip(peer, allowed_clients)
    end
  end

  defp get_peercert(%{transport: transport, socket: socket} = peer) do
    transport.name()
    |> get_peercert(socket)
    |> case do
      {:ok, cert} ->
        Map.put_new(peer, :cert, cert)
        |> OK.wrap()

      {:error, error} ->
        Logger.warn("Error in getting peer cert #{inspect(error)}")
        {:error, :no_peercert}
    end
  end

  defp get_peercert(sslmodule, socket) do
    sslmodule.peercert(socket)
  end

  defp verify_host_name(_peer, allowed_clients) when allowed_clients in [nil, []],
    do: {:ok, :success}

  defp verify_host_name(%{cert: cert}, allowed_clients) do
    reference_ids =
      for allowed_client <- allowed_clients do
        {:cn, allowed_client}
      end

    if :public_key.pkix_verify_hostname(
         cert,
         reference_ids,
         fqdn_fun: &fqdn_fun/1,
         match_fun: &match_fun/2
       ) do
      {:ok, :success}
    else
      {:error, :fail_to_verify_client_cert}
    end
  end

  defp match_fun({:cn, reference}, {_, presented}) do
    presented == reference
  end

  defp match_fun(reference, {_, presented}) do
    presented == reference
  end

  defp fqdn_fun({:cn, value}) do
    value
  end

  defp validate_client_ip(%{client_info: {_ip, _port}}, []), do: {:ok, :success}

  defp validate_client_ip(%{client_info: {ip, _port}}, allowed_clients) do
    if ip in allowed_clients do
      {:ok, :success}
    else
      {:error, :client_ip_not_allowed}
    end
  end

  defp validate_client_ip(_, _), do: {:error, :client_ip_not_allowed}
end
