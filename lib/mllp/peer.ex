defmodule MLLP.Peer do
  use OK.Pipe
  require Logger

  import Record, only: [defrecordp: 3, extract: 2]

  defrecordp(
    :certificate,
    :Certificate,
    extract(:Certificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  defrecordp(
    :tbs_certificate,
    :OTPTBSCertificate,
    extract(:OTPTBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  @type t :: %{
          :transport => :ranch_tcp | :ranch_ssl,
          :socket => :ranch_transport.socket(),
          :client_info => {:inet.ip_address(), :inet.port_number()},
          optional(:cert) => binary() | :undefined | nil
        }

  @type error_type ::
          :client_ip_not_allowed
          | :no_peercert
          | :invalid_verify_option
          | :fail_to_verify_client_cert_hostname

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

  def get_peercert(%{transport: transport, socket: socket} = peer) do
    case transport.name() do
      :ssl ->
        :ssl.peercert(socket)
        |> case do
          {:ok, cert} ->
            Map.put_new(peer, :cert, cert)
            |> OK.wrap()

          {:error, error} ->
            Logger.warn("Error in getting peer cert #{inspect(error)}")
            {:error, :no_peercert}
        end

      _ ->
        {:error, :invalid_verify_option}
    end
  end

  defp verify_host_name(_cert, allowed_clients) when allowed_clients in [nil, []],
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
      {:error, :fail_to_verify_client_cert_hostname}
    end
  end

  defp verify_host_name(_, _), do: {:error, :fail_to_verify_client_cert_hostname}

  defp match_fun(references, {:cn, presented}) do
    presented == references
  end

  defp fqdn_fun({:cn, value}) do
    value
  end

  # defp inspect_cert(peer_cert, _options \\ []) do
  #   decoded_cert =
  #     :public_key.pkix_decode_cert(peer_cert, :otp)
  #     |> IO.inspect(label: :decoded_cert)

  #   # IO.inspect(subject_id: :public_key.pkix_subject_id(peer_cert))
  #   # {:ok, {_, issuer_name}} = :public_key.pkix_issuer_id(peer_cert, :self)
  #   # IO.inspect(issuer_name: :public_key.pkix_normalize_name(issuer_name))

  #   IO.inspect(cert_expired: cert_expired?(decoded_cert))

  #   # IO.inspect(
  #   #   trusted:
  #   #     trusted?(
  #   #       :public_key.pkix_decode_cert(peer_cert, :plain),
  #   #       Keyword.get(options, :cacertfile)
  #   #     )
  #   # )

  #   valid_names = ['client-1']

  #   :public_key.pkix_verify_hostname(
  #     peer_cert,
  #     [cn: valid_names],
  #     fqdn_fun: &fqdn_fun/1,
  #     match_fun: &match_fun/2
  #   )
  #   |> IO.inspect(label: :is_valid_host_name)
  # end

  # defp cert_expired?(cert) do
  #   {:Validity, not_before, not_after} =
  #     cert
  #     |> certificate(:tbsCertificate)
  #     |> tbs_certificate(:validity)
  #     |> IO.inspect(label: :validity)

  #   now = DateTime.utc_now()

  #   DateTime.compare(now, to_datetime!(not_before)) == :lt or
  #     DateTime.compare(now, to_datetime!(not_after)) == :gt
  # end

  # defp to_datetime!({:utcTime, time}) do
  #   "20#{time}"
  #   |> to_datetime!()
  # end

  # defp to_datetime!({:generalTime, time}) do
  #   time
  #   |> to_string()
  #   |> to_datetime!()
  # end

  # defp to_datetime!(
  #        <<year::binary-size(4), month::binary-size(2), day::binary-size(2), hour::binary-size(2),
  #          minute::binary-size(2), second::binary-size(2), "Z"::binary>>
  #      ) do
  #   {:ok, datetime, _} =
  #     DateTime.from_iso8601("#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z")

  #   datetime
  # end

  # defp trusted?(peer_cert, cacertfile) do
  #   peer_cert_public_key = extract_public_key_info(peer_cert)

  #   File.read!(cacertfile)
  #   # |> IO.inspect(label: :cacert)
  #   |> :public_key.pem_decode()
  #   # |> IO.inspect(label: :pem_decode)
  #   |> Enum.filter(&match?({:Certificate, _, :not_encrypted}, &1))
  #   # |> IO.inspect(label: :pem_decode_after_filter)
  #   |> Enum.map(&:public_key.pem_entry_decode/1)
  #   # |> IO.inspect(label: :decoded_certs)
  #   |> Enum.any?(fn decoded_cert ->
  #     peer_cert_public_key == extract_public_key_info(decoded_cert)
  #   end)
  # end

  # defp extract_public_key_info(cert) do
  #   cert
  #   |> certificate(:tbsCertificate)
  #   |> tbs_certificate(:subjectPublicKeyInfo)
  #   |> IO.inspect(label: :subjectPublicKeyInfo)
  # end

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
