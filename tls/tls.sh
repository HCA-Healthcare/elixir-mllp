cd tls

mkdir root-ca client client_mixed_case_cn server expired_client
cd root-ca
rm index.txt
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
    -subj /CN=client-1/O=client/ -addext 'subjectAltName = DNS:client-1' -nodes

cd ../root-ca
openssl ca -config ../openssl.cnf -in ../client/req.pem -out \
    ../client/client_certificate.pem -notext -batch -extensions client_ca_extensions

#Client Cert with mixed case CN
cd ../client_mixed_case_cn

openssl genrsa -out private_key.pem 2048
openssl req -new -key private_key.pem -out req.pem -outform PEM \
    -subj /CN=MIXED-CASE-client-cert/O=client/ -nodes

cd ../root-ca
openssl ca -config ../openssl.cnf -in ../client_mixed_case_cn/req.pem -out \
    ../client_mixed_case_cn/client_certificate.pem -notext -batch -extensions client_ca_extensions

#Client Expired Cert
cd ../expired_client

openssl genrsa -out private_key.pem 2048
openssl req -new -key private_key.pem -out req.pem -outform PEM \
    -subj /CN=expired-client-cert/O=client/ -nodes

cd ../root-ca
openssl ca -config ../openssl.cnf -in ../expired_client/req.pem -out \
    ../expired_client/client_certificate.pem -startdate 200101000000Z -enddate 201231000000Z -notext -batch -extensions client_ca_extensions

cd ..
cd ..

