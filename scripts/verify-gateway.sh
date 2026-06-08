#!/usr/bin/env sh
set -eu

BASE_URL="${1:-http://127.0.0.1:8081}"

check_url() {
  url="$1"
  expected="${2:-200}"
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' "$url")"
  if [ "$code" != "$expected" ]; then
    echo "FAIL $url -> $code, expected $expected"
    exit 1
  fi
  echo "OK   $url -> $code"
}

check_url "${BASE_URL%/}/guacamole/" 200

echo "Gateway check passed."
