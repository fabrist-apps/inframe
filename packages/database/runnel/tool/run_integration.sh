#!/usr/bin/env bash
set -euo pipefail

RUNNEL_TEST_DIR="$(mktemp -d)"
RUNNEL_REDIS_CONTAINER="runnel-redis-$$"
RUNNEL_VALKEY_CONTAINER="runnel-valkey-$$"

cleanup() {
  docker stop "$RUNNEL_REDIS_CONTAINER" "$RUNNEL_VALKEY_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$RUNNEL_TEST_DIR"
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj /CN=Runnel-Test-CA \
  -addext basicConstraints=critical,CA:TRUE,pathlen:0 \
  -addext keyUsage=critical,keyCertSign,cRLSign \
  -addext subjectKeyIdentifier=hash \
  -keyout "$RUNNEL_TEST_DIR/ca.key" \
  -out "$RUNNEL_TEST_DIR/ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes \
  -subj /CN=localhost \
  -keyout "$RUNNEL_TEST_DIR/server.key" \
  -out "$RUNNEL_TEST_DIR/server.csr" >/dev/null 2>&1

RUNNEL_TLS_EXTENSIONS="$RUNNEL_TEST_DIR/server.ext"
{
  echo 'subjectAltName=DNS:localhost,IP:127.0.0.1'
  echo 'basicConstraints=critical,CA:FALSE'
  echo 'keyUsage=critical,digitalSignature,keyEncipherment'
  echo 'extendedKeyUsage=serverAuth'
  echo 'subjectKeyIdentifier=hash'
  echo 'authorityKeyIdentifier=keyid,issuer'
} >"$RUNNEL_TLS_EXTENSIONS"

openssl x509 -req \
  -in "$RUNNEL_TEST_DIR/server.csr" \
  -CA "$RUNNEL_TEST_DIR/ca.crt" \
  -CAkey "$RUNNEL_TEST_DIR/ca.key" \
  -CAcreateserial \
  -days 365 \
  -extfile "$RUNNEL_TLS_EXTENSIONS" \
  -out "$RUNNEL_TEST_DIR/server.crt" >/dev/null 2>&1
chmod 644 "$RUNNEL_TEST_DIR"/*.key "$RUNNEL_TEST_DIR"/*.crt
chmod 755 "$RUNNEL_TEST_DIR"

docker run --detach --rm --name "$RUNNEL_REDIS_CONTAINER" \
  --publish 127.0.0.1:16379:6379 \
  --publish 127.0.0.1:16380:6380 \
  --volume "$RUNNEL_TEST_DIR:/tls:ro" \
  redis:8.2.1@sha256:5fa2edb1e408fa8235e6db8fab01d1afaaae96c9403ba67b70feceb8661e8621 \
  redis-server \
  --requirepass test-password \
  --port 6379 \
  --tls-port 6380 \
  --tls-cert-file /tls/server.crt \
  --tls-key-file /tls/server.key \
  --tls-ca-cert-file /tls/ca.crt \
  --tls-auth-clients no >/dev/null

docker run --detach --rm --name "$RUNNEL_VALKEY_CONTAINER" \
  --publish 127.0.0.1:17379:6379 \
  --publish 127.0.0.1:17380:6380 \
  --volume "$RUNNEL_TEST_DIR:/tls:ro" \
  valkey/valkey:8.1.3@sha256:fea8b3e67b15729d4bb70589eb03367bab9ad1ee89c876f54327fc7c6e618571 \
  valkey-server \
  --requirepass test-password \
  --port 6379 \
  --tls-port 6380 \
  --tls-cert-file /tls/server.crt \
  --tls-key-file /tls/server.key \
  --tls-ca-cert-file /tls/ca.crt \
  --tls-auth-clients no >/dev/null

for attempt in {1..60}; do
  if docker exec "$RUNNEL_REDIS_CONTAINER" redis-cli -a test-password ping >/dev/null 2>&1 && \
    docker exec "$RUNNEL_VALKEY_CONTAINER" valkey-cli -a test-password ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$RUNNEL_REDIS_CONTAINER" redis-cli -a test-password ping >/dev/null
docker exec "$RUNNEL_VALKEY_CONTAINER" valkey-cli -a test-password ping >/dev/null

RUNNEL_URL='redis://:test-password@127.0.0.1:16379' \
  dart run packages/database/runnel/example/runnel_example.dart >/dev/null

RUNNEL_REDIS_URL='redis://:test-password@127.0.0.1:16379' \
RUNNEL_REDIS_TLS_URL='rediss://:test-password@localhost:16380' \
RUNNEL_VALKEY_URL='redis://:test-password@127.0.0.1:17379' \
RUNNEL_VALKEY_TLS_URL='rediss://:test-password@localhost:17380' \
RUNNEL_TLS_CA="$RUNNEL_TEST_DIR/ca.crt" \
  dart test packages/database/runnel/test/integration --chain-stack-traces
