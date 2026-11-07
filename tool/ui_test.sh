#!/usr/bin/env bash
# Run the hermetic UI tests against the real macOS app and an in-process fake
# object server. Needs no credentials and never talks to a real server.
#
# Note: this builds into the same build/ dir as `flutter run`; quit a running
# dev instance first (the script warns if one is running).
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x dbbasic_scroll >/dev/null; then
  echo "A dbbasic_scroll instance is running; quit it first (it shares build/)." >&2
  exit 2
fi
# "all": every UI test file, one flutter invocation each (macOS can't start a
# second app within one invocation: "Unable to start the app on the device").
if [[ "${1:-}" == "all" ]]; then
  shift
  status=0
  for f in integration_test/connect_flow_test.dart integration_test/screen_sweep_test.dart; do
    echo "=== $f"
    flutter test "$f" -d macos "$@" || status=$?
  done
  exit $status
fi
# "sandbox": the real-server suite against tool/desk_sandbox.sh (local only).
# "sweep": every screen, password-signed-in (sandbox started with SESSION_ADMIN=1).
# "genui": the server's generative UI (apps launcher, views, blocks) natively.
if [[ "${1:-}" == "sandbox" || "${1:-}" == "sweep" || "${1:-}" == "genui" ]]; then
  file=integration_test/sandbox_test.dart
  [[ $1 == sweep ]] && file=integration_test/sandbox_sweep_test.dart
  [[ $1 == genui ]] && file=integration_test/generative_ui_test.dart
  shift
  SB=build/desk-sandbox
  [[ -s $SB/admin_token ]] || { echo "start it first: tool/desk_sandbox.sh start" >&2; exit 2; }
  exec flutter test "$file" -d macos \
    --dart-define=SANDBOX_API_KEY="$(cat $SB/dan_api_key)" \
    --dart-define=SANDBOX_ADMIN_TOKEN="$(cat $SB/admin_token)" \
    --dart-define=SANDBOX_PASSWORD="$(cat $SB/dan_password)" "$@"
fi
# Optional first arg: a specific test file (default: the connect-flow suite).
target=integration_test/connect_flow_test.dart
if [[ "${1:-}" == *.dart ]]; then target="$1"; shift; fi
exec flutter test "$target" -d macos "$@"
