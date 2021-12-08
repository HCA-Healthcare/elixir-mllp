defmodule MLLP.Peer do
  use OK.Pipe

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
          transport: :ranch_tcp | :ranch_ssl,
          socket: :ranch_transport.socket(),
          client_info: {:inet.ip_address(), :inet.port_number()}
        }

  @type error_type ::
          :client_ip_not_allowed
          | :invalid_peer_cert
          | :no_peercert
          | :invalid_verify_option_on_tcp_connection

  @spec validate(t(), Keyword.t()) :: {:ok, :success} | {:error, error_type()}

  def validate(peer, options) do
    allowed_clients = Keyword.get(options, :allowed_clients, [])
    verify_peer = Keyword.get(options, :verify_peer, false)

    validate_client_ip(peer, allowed_clients)
    ~>> validate_cert(verify_peer)
  end

  defp validate_cert(_peer, false), do: {:ok, :success}

  defp validate_cert(peer, _) do
    case get_peer_cert(peer.transport, peer.socket) do
      {:ok, _cert} ->
        {:ok, :success}

      error ->
        error
    end
  end

  def get_peer_cert(transport, socket) do
    case transport.name() do
      :ssl ->
        :ssl.peercert(socket)

      _ ->
        {:error, :invalid_verify_option_on_tcp_connection}
    end
  end

  # defp validate(peer_cert, options) do
  #   IO.inspect(peer_cert: peer_cert)

  #   decoded_cert =
  #     :public_key.pkix_decode_cert(peer_cert, :otp)
  #     |> IO.inspect(label: :decoded_cert)

  #   IO.inspect(subject_id: :public_key.pkix_subject_id(peer_cert))
  #   IO.inspect(issuer_id: :public_key.pkix_issuer_id(peer_cert, :self))
  #   IO.inspect(cert_expired: cert_expired?(decoded_cert))

  #   IO.inspect(
  #     trusted:
  #       trusted?(
  #         :public_key.pkix_decode_cert(peer_cert, :plain),
  #         Keyword.get(options, :cacertfile)
  #       )
  #   )

  #   valid_names = ['baxter-hl7-sender3', 'baxter-hl7-sender2', 'baxter-hl7-sender']

  #   :public_key.pkix_verify_hostname(
  #     peer_cert,
  #     [cn: valid_names],
  #     fqdn_fun: &fqdn_fun/1,
  #     match_fun: &match_fun/2
  #   )
  #   |> IO.inspect(label: :is_valid_host_name)
  # end

  # defp match_fun(references, {:cn, presented}) do
  #   IO.inspect(references: references)
  #   IO.inspect(presented: presented)
  #   presented in references
  # end

  # defp fqdn_fun({:cn, value}) do
  #   IO.inspect(fqdn_fun: value)
  #   value
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

  defp validate_client_ip(%{client_info: {_ip, _port}} = peer, []), do: {:ok, peer}

  defp validate_client_ip(%{client_info: {ip, _port}} = peer, allowed_clients) do
    if ip in allowed_clients do
      {:ok, peer}
    else
      {:error, :client_ip_not_allowed}
    end
  end
end
