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

  @spec validate(t(), map()) :: {:ok, :success} | {:error, error_type()}

  def validate(_, %{allowed_clients: allowed_clients}) when allowed_clients == %{} do
    {:ok, :success}
  end

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
      {:ok, :success}
    else
      {:error, :fail_to_verify_client_cert}
    end
  end

  defp match_fun({:cn, reference}, {_, reference}), do: true
  defp match_fun(reference, {_, reference}), do: true
  defp match_fun(_, _), do: false

  defp fqdn_fun({:cn, value}), do: value

  defp verify_client_ip({ip, _port}, allowed_clients)
       when is_map_key(allowed_clients, ip) do
    {:ok, :success}
  end

  defp verify_client_ip(_, _), do: {:error, :client_ip_not_allowed}
end
