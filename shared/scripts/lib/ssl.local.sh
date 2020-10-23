#!/bin/bash
set -eou pipefail

dir_prefix="${1:-}"
name="${2:-localhost}"

if [ -n "$dir_prefix" ]; then
	mkdir -p "$dir_prefix"
	dir_prefix="$dir_prefix/"
fi

############################################
# Become a Certificate Authority
############################################

# Generate private key
openssl genrsa -des3 -out "${dir_prefix}ca.key" 2048

# Generate root certificate
openssl req -x509 -new -nodes -key "${dir_prefix}ca.key" -sha256 -days 36500 -out "${dir_prefix}ca.pem"

############################################
# Create CA-signed certs
############################################

# Generate a private key
openssl genrsa -out "${dir_prefix}${name}.key" 2048

# Create a certificate-signing request
openssl req -new -key "${dir_prefix}${name}.key" -out "${dir_prefix}${name}.csr"

# Create a config file for the extensions
>"${dir_prefix}${name}.ext" cat <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = $name
DNS.2 = *.$name
EOF

# Create the signed certificate
openssl x509 -req -in "${dir_prefix}${name}.csr" \
	-CA "${dir_prefix}ca.pem" -CAkey "${dir_prefix}ca.key" -CAcreateserial \
	-out "${dir_prefix}${name}.crt" -days 36500 -sha256 -extfile "${dir_prefix}${name}.ext"

# create the bundle
cat "${dir_prefix}${name}.crt" "${dir_prefix}ca.pem" > "${dir_prefix}bundle.crt"
