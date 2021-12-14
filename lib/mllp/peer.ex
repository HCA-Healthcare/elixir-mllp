defmodule MLLP.Peer do
  require Logger

  @type t :: %{
          :transport => :ranch_tcp | :ranch_ssl,
          :socket => :ranch_transport.socket(),
          :client_info => {:inet.ip_address(), :inet.port_number()}
        }

  @type error_type ::
          :client_ip_not_allowed
          | :fail_to_verify_client_cert

  @spec validate(t(), Keyword.t()) :: {:ok, :success} | {:error, error_type()}

  def validate(peer, options) do
    allowed_clients = Keyword.get(options, :allowed_clients, [])
    verify_peer = Keyword.get(options, :verify_peer, false)

    verify(peer, %{allowed_client: allowed_clients, verify_peer: verify_peer})
  end

  defp verify(%{transport: transport, socket: socket}, %{
         allowed_client: allowed_clients,
         verify_peer: true
       }) do
    case transport.name().peercert(socket) do
      {:ok, cert} ->
        verify_host_name(cert, allowed_clients)

      {:error, error} ->
        {:error, error}
    end
  end

  defp verify(%{client_info: client_info}, %{allowed_client: allowed_clients}) do
    verify_client_ip(client_info, allowed_clients)
  end

  defp verify_host_name(_cert, allowed_clients) when allowed_clients in [nil, []],
    do: {:ok, :success}

  defp verify_host_name(cert, allowed_clients) do
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

  defp verify_client_ip(_, []), do: {:ok, :success}

  defp verify_client_ip({ip, _port}, allowed_clients) do
    if ip in allowed_clients do
      {:ok, :success}
    else
      {:error, :client_ip_not_allowed}
    end
  end

  defp verify_client_ip(_, _), do: {:error, :client_ip_not_allowed}
end
