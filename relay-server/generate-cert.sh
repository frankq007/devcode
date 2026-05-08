#!/bin/bash

mkdir -p cert

openssl genrsa -out cert/server.key 2048

openssl req -new -x509 -days 365 -key cert/server.key \
  -out cert/server.crt \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=DevCode/OU=Relay/CN=devcode-relay"

echo "SSL certificates generated in cert/"
echo "  - cert/server.key"
echo "  - cert/server.crt"