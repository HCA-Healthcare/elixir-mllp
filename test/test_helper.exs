should_generate_cert = fn ->
  folder_exists =
    File.exists?("tls") && File.exists?("tls/root-ca") && File.exists?("tls/server") &&
      File.exists?("tls/client") && File.exists?("tls/expired_client")

  how_old_in_days =
    File.lstat("tls/root-ca/index.txt", time: :posix)
    |> case do
      {:ok, file_stat} ->
        last_modified_time = file_stat.mtime |> DateTime.from_unix!()
        DateTime.diff(DateTime.utc_now(), last_modified_time) / (3600 * 24)

      _ ->
        365
    end

  how_old_in_days > 360 || !folder_exists
end

if should_generate_cert.(), do: System.cmd("sh", ["tls/tls.sh"])

ExUnit.start()

defmodule MLLP.TestHelper.Utils do
  def otp_release() do
    :erlang.system_info(:otp_release)
    |> to_string()
    |> String.to_integer()
  end
end
