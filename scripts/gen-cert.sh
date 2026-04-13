#!/usr/bin/env bash
# Generate a self-signed TLS certificate.
#
# Usage:
#   bash scripts/gen-cert.sh [output-dir] [ip-or-domain ...]
#
# Each extra argument can be a single value or comma-separated list.
# Examples:
#   bash scripts/gen-cert.sh ./certs                                    # localhost only
#   bash scripts/gen-cert.sh ./certs 1.2.3.4                            # + IP
#   bash scripts/gen-cert.sh ./certs 1.2.3.4 example.com               # + IP + domain
#   bash scripts/gen-cert.sh ./certs 1.2.3.4,10.0.0.1 a.com,b.com      # comma-separated
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
  # Split on commas to allow "1.2.3.4,5.6.7.8" or "a.com,b.com"
  IFS=',' read -ra tokens <<< "$arg"
  for token in "${tokens[@]}"; do
    [[ -z "$token" ]] && continue
    # Detect IPv4 / IPv6 vs hostname
    if [[ "$token" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
       [[ "$token" =~ ^[0-9a-fA-F:]+$ && "$token" == *:* ]]; then
      ALT_NAMES+="IP.${IP_IDX}  = ${token}\n"
      (( IP_IDX++ ))
    else
      ALT_NAMES+="DNS.${DNS_IDX} = ${token}\n"
      (( DNS_IDX++ ))
    fi
  done
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
