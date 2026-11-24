
#!/usr/bin/env bash

# VPS Verification - No Tailscale

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

FAILED=0

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

fail() {
    echo -e "${RED}[FAILED]${NC} $*"
    FAILED=$((FAILED + 1))
}

echo "=================================="
echo "       VPS VERIFICATION"
echo "=================================="

for cmd in git python3 node npm tmate sshd; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd installed"
    else
        fail "$cmd missing"
    fi
done

if sudo systemctl is-active --quiet ssh; then
    ok "SSH service running"
else
    fail "SSH service not running"
fi

if sudo sshd -t; then
    ok "SSH configuration valid"
else
    fail "SSH configuration invalid"
fi

VPS_USER="${VPS_USER:-kawsar}"

if id "$VPS_USER" >/dev/null 2>&1; then
    ok "VPS user exists: $VPS_USER"
else
    fail "VPS user missing"
fi

if command -v docker >/dev/null 2>&1; then
    if sudo systemctl is-active --quiet docker; then
        ok "Docker service running"
    else
        fail "Docker service not running"
    fi
fi

echo "=================================="

if [ "$FAILED" -gt 0 ]; then
    echo "$FAILED verification check(s) failed."
    exit 1
fi

echo "ALL CHECKS PASSED"
echo "VPS READY"
echo "=================================="
