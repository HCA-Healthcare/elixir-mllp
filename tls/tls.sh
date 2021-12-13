cd tls

mkdir root-ca client server
cd root-ca
rm -f index.txt
touch index.txt
echo 01 > serial
mkdir certs private

openssl req -x509 -sha256 -days 1825 -newkey rsa:2048 -config ../openssl.cnf -out ca_certificate.pem -outform PEM -subj /CN=waterpark-internal-root-ca/ -nodes
openssl x509 -in ca_certificate.pem -out ca_certificate.cer -outform DER

#Server Cert
cd ../server

# generate a req
openssl genrsa -out private_key.pem 2048
openssl req -new -key private_key.pem -out req.pem -outform PEM \
    -subj /CN=localhost/O=server/ -nodes

cd ../root-ca

# sign request with root-ca
openssl ca -config ../openssl.cnf -in ../server/req.pem -out \
    ../server/server_certificate.pem -notext -batch -extensions server_ca_extensions


#Client Cert
cd ../client

openssl genrsa -out private_key.pem 2048
openssl req -new -key private_key.pem -out req.pem -outform PEM \
    -subj /CN=client-1/O=client/ -nodes

cd ../root-ca
openssl ca -config ../openssl.cnf -in ../client/req.pem -out \
    ../client/client_certificate.pem -notext -batch -extensions client_ca_extensions

cd ..
cd ..
