
#/bin/sh
set -e

# Make the current dir to be the working dir
parent_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P)
cd "$parent_path"

# Some files and directories needed
mkdir -p build/newcerts
mkdir -p build/aux
touch build/aux/index.txt
echo '01' > build/aux/serial

# Generate ca.key
openssl genrsa -out build/ca.key 2048

# Generate ca.crt
openssl req -new -x509 -key build/ca.key -out build/ca.crt -config ca-gen.conf

# Generate server.key
openssl genrsa -out build/server.key 2048

# Generate server.csr
openssl req -new -key build/server.key -out build/server.csr -config server.conf

# Generate server.crt
openssl ca -batch -config ca.conf -out build/server.crt -infiles build/server.csr