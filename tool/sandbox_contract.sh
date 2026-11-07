#!/usr/bin/env bash
# Run the API contract test against the local desk sandbox (real server code).
set -euo pipefail
cd "$(dirname "$0")/.."
SB=build/desk-sandbox
[[ -s $SB/admin_token ]] || { echo "start it first: tool/desk_sandbox.sh start" >&2; exit 2; }
exec flutter test test/sandbox_contract_test.dart \
  --dart-define=SANDBOX_API_KEY="$(cat $SB/dan_api_key)" \
  --dart-define=SANDBOX_ADMIN_TOKEN="$(cat $SB/admin_token)" \
  --dart-define=SANDBOX_PASSWORD="$(cat $SB/dan_password)" "$@"
