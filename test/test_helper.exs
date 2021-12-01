ExUnit.start()
if not File.exists?("tls/root-ca"), do: System.cmd("sh", ["tls/tls.sh"])
