#!/usr/bin/env bash
# Generate a self-signed TLS certificate.
#
# Usage:
#   bash scripts/gen-cert.sh [output-dir] [ip-or-domain ...]
#
# Examples:
#   bash scripts/gen-cert.sh ./certs                          # localhost only
#   bash scripts/gen-cert.sh ./certs 10.200.10.1              # + LAN IP
#   bash scripts/gen-cert.sh ./certs 10.200.10.1 example.com  # + IP + domain
set -euo pipefail

OUT=${1:-./certs}
shift || true          # remaining args are extra IPs / domains
mkdir -p "$OUT"

OPENSSL_CNF=$(mktemp /tmp/rc-openssl-XXXX.cnf)
trap 'rm -f "$OPENSSL_CNF"' EXIT

# Always include localhost + 127.0.0.1; add extras from CLI args
DNS_IDX=2
IP_IDX=2
ALT_NAMES="DNS.1 = localhost\nIP.1  = 127.0.0.1\n"

for arg in "$@"; do
  # Detect IPv4 / IPv6 vs hostname
  if [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
     [[ "$arg" =~ ^[0-9a-fA-F:]+$ && "$arg" == *:* ]]; then
    ALT_NAMES+="IP.${IP_IDX}  = ${arg}\n"
    (( IP_IDX++ ))
  else
    ALT_NAMES+="DNS.${DNS_IDX} = ${arg}\n"
    (( DNS_IDX++ ))
  fi
done

cat > "$OPENSSL_CNF" <<EOF
[req]
default_bits       = 2048
default_md         = sha256
prompt             = no
distinguished_name = dn
x509_extensions    = v3_req

[dn]
CN = remotectl

[v3_req]
subjectAltName     = @alt_names
basicConstraints   = CA:FALSE
keyUsage           = critical, digitalSignature, keyEncipherment
extendedKeyUsage   = serverAuth

[alt_names]
$(printf '%b' "$ALT_NAMES")
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$OUT/server.key" \
  -out    "$OUT/server.crt" \
  -config "$OPENSSL_CNF" 2>/dev/null

echo "Certificate : $OUT/server.crt"
echo "Key         : $OUT/server.key"
echo ""
echo "SANs included:"
openssl x509 -in "$OUT/server.crt" -noout -ext subjectAltName 2>/dev/null | grep -v "^X509"
echo ""
echo "Start server:"
echo "  ./bin/remotectl-server --tls-cert $OUT/server.crt --tls-key $OUT/server.key"
