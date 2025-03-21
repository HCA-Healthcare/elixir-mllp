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

  @type peer_name :: String.t() | :inet.ip_address()

  @spec validate(t(), map()) :: {:ok, peer_name()} | {:error, error_type()}

  def validate(peer, %{allowed_clients: allowed_clients, verify: :verify_peer}) do
    %{transport: transport, socket: socket} = peer

    case transport.name().peercert(socket) do
      {:ok, cert} ->
        verify_host_name(cert, allowed_clients)

      {:error, error} ->
        {:error, error}
    end
  end

  def validate(%{client_info: client_info}, %{allowed_clients: allowed_clients}) do
    verify_client_ip(client_info, allowed_clients)
  end

  defp verify_host_name(cert, allowed_clients) when allowed_clients == %{} do
    {:ok, get_common_name(cert)}
  end

  defp verify_host_name(cert, allowed_clients) do
    reference_ids =
      Map.keys(allowed_clients)
      |> Enum.into([], fn allowed_client -> {:cn, allowed_client} end)

    if :public_key.pkix_verify_hostname(
         cert,
         reference_ids,
         fqdn_fun: &fqdn_fun/1,
         match_fun: &match_fun/2
       ) do
      {:ok, get_common_name(cert)}
    else
      {:error, :fail_to_verify_client_cert}
    end
  end

  defp match_fun({:cn, reference_id}, {_, peer_cn}) do
    match_cn?(reference_id, peer_cn)
  end

  defp match_fun(reference_id, {_, peer_cn}) do
    match_cn?(reference_id, peer_cn)
  end

  defp match_fun(_, _), do: false

  defp match_cn?(reference_id, peer_cn) do
    :string.equal(reference_id, peer_cn, true)
  end

  defp fqdn_fun({:cn, value}), do: value

  defp verify_client_ip({ip, _port}, allowed_clients) when allowed_clients == %{} do
    {:ok, ip}
  end

  defp verify_client_ip({ip, _port}, allowed_clients)
       when is_map_key(allowed_clients, ip) do
    {:ok, ip}
  end

  defp verify_client_ip(_, _), do: {:error, :client_ip_not_allowed}

  defp get_common_name(cert) do
    {_, {:rdnSequence, cert_attributes}} = :public_key.pkix_subject_id(cert)

    cert_attributes
    |> Enum.find_value(fn
      [{:AttributeTypeAndValue, oid, {_, value}}] -> if oid == {2, 5, 4, 3}, do: value
      _ -> nil
    end)
  end
end
