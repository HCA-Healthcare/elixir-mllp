File.exists?("tls/root-ca") || System.cmd("sh", ["tls/tls.sh"])
ExUnit.start()
