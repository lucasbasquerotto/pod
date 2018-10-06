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

# Generate oats.key
openssl genrsa -out build/oats.key 2048

# Generate oats.csr
openssl req -new -key build/oats.key -out build/oats.csr -config oats.conf

# Generate oats.crt
openssl ca -batch -config ca.conf -out build/oats.crt -infiles build/oats.csr