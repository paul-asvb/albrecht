#!/usr/bin/env bash
# Export the in-cluster sslip-ca root certificate and add it to the system and
# browser trust stores, so HTTPS to *.sslip.io services stops triggering
# "Something doesn't look right" warnings.
#
# Re-run after cert-manager rotates the CA (~every 90 days).
# Requires: kubectl, sudo, and (for browsers) nss/certutil.
#
# Usage: scripts/trust-ca.sh
#   KUBECONFIG defaults to /tmp/volmar.yaml if unset.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/tmp/volmar.yaml}"
CA_FILE="/tmp/sslip-ca.crt"

echo "==> Extracting sslip-ca root certificate..."
kubectl get secret sslip-ca-secret -n cert-manager \
    -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CA_FILE"

echo "==> Installing into system trust store (sudo)..."
sudo cp "$CA_FILE" /etc/ca-certificates/trust-source/anchors/sslip-ca.crt
sudo trust extract-compat

echo "==> Installing into browser NSS stores..."
if ! command -v certutil >/dev/null; then
    echo "  certutil not found — skipping browsers (install with: sudo pacman -S nss)"
else
    for db in "$HOME/.pki/nssdb" "$HOME"/.mozilla/firefox/*/; do
        if [ -d "$db" ] && { [ -f "$db/cert9.db" ] || [ -f "$db/cert8.db" ]; }; then
            certutil -d "sql:$db" -D -n sslip-ca 2>/dev/null || true
            if certutil -d "sql:$db" -A -t "C,," -n sslip-ca -i "$CA_FILE"; then
                echo "  trusted in $db"
            else
                echo "  failed in $db"
            fi
        fi
    done
fi

echo "Done. Restart your browser, then test:"
echo "  curl https://plattform.default.192.168.1.249.sslip.io/health"
