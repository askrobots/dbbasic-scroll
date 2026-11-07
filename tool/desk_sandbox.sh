#!/usr/bin/env bash
# A local, throwaway copy of the nc desk's object server for testing Scroll
# against REAL server code without touching live data.
#
#   tool/desk_sandbox.sh start [commit]   # default: 6707021 (what the desk runs)
#   tool/desk_sandbox.sh stop
#   tool/desk_sandbox.sh status
#
# Same feature flags as the desk (provision/apply.sh), same bootstrap
# (superuser "dan", the 12 app-* packages, a user API key). Everything lives in
# build/desk-sandbox (gitignored). Secrets are written to 0600 files there and
# never printed: admin_token, dan_password, dan_api_key.
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER_REPO=${SERVER_REPO:-/Volumes/T9/dbbasic-object-server-work}
SB=build/desk-sandbox
PORT=${SANDBOX_PORT:-18101}
URL=http://127.0.0.1:$PORT

stop() {
  if [[ -f $SB/server.pid ]] && kill -0 "$(cat $SB/server.pid)" 2>/dev/null; then
    kill "$(cat $SB/server.pid)"; echo "sandbox stopped"
  fi
  rm -f $SB/server.pid
  # Also an orphaned sandbox server still holding the port (e.g. a start whose
  # pid file was overwritten). Only kill it if it is really our uvicorn.
  for pid in $(lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null); do
    if ps -o command= -p "$pid" | grep -q "uvicorn object_server:app.*--port $PORT"; then
      kill "$pid" && echo "stopped orphaned sandbox server (pid $pid)"
    fi
  done
  for _ in $(seq 20); do lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || break; sleep 0.25; done
}

case "${1:-}" in
  stop) stop; exit 0 ;;
  status)
    curl -s -m 3 "$URL/health?format=json" && echo " ($URL)" || echo "sandbox not running"
    exit 0 ;;
  start) ;;
  *) echo "usage: $0 start [commit]|stop|status" >&2; exit 2 ;;
esac

COMMIT=${2:-6707021}
stop
if lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "port $PORT is busy with something that is not the sandbox; set SANDBOX_PORT" >&2; exit 1
fi
rm -rf $SB && mkdir -p $SB/code $SB/data $SB/objects
git -C "$SERVER_REPO" archive "$COMMIT" | tar -x -C $SB/code
echo "$COMMIT" > $SB/commit
(umask 077
 head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32 > $SB/admin_token
 head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24 > $SB/dan_password)

ABS=$(cd $SB && pwd)
env_args=(
  DBBASIC_ADMIN_TOKEN="$(cat $SB/admin_token)"
  DBBASIC_DATA_DIR="$ABS/data" DBBASIC_OBJECTS_DIR="$ABS/objects"
  DBBASIC_PACKAGES_DIR="$ABS/code/packages"
  DBBASIC_COOKIE_SECURE=false PYTHONDONTWRITEBYTECODE=1
)
for f in AI_CHAT TTS STT READER SITE_ROUTES PACKAGE_INSTALLS USER_FILES \
         PASSWORD_LOGIN PERMISSION_ENFORCEMENT WEBDAV; do
  env_args+=("DBBASIC_ENABLE_$f=true")
done
# SESSION_ADMIN=1: also let admin-role password sessions pass the admin gates
# (the server's documented path for Scroll; off on the desk today).
[[ ${SESSION_ADMIN:-0} == 1 ]] && env_args+=("DBBASIC_ENABLE_SESSION_ADMIN_GATES=true")

(cd $SB/code && env "${env_args[@]}" nohup python3 -m uvicorn object_server:app \
   --host 127.0.0.1 --port "$PORT" --log-level info < /dev/null > "$ABS/server.log" 2>&1 & echo $! > "$ABS/server.pid")
for _ in $(seq 40); do curl -sf -m 2 "$URL/health" >/dev/null && break; sleep 0.5; done
curl -sf -m 2 "$URL/health" >/dev/null || { echo "server failed to start; see $SB/server.log" >&2; tail -20 $SB/server.log >&2; exit 1; }
echo "sandbox up at $URL (commit $COMMIT)"

# Bootstrap exactly like nc-object-bootstrap: superuser dan, packages, an API key.
(cd $SB/code && env "${env_args[@]}" python3 object_identity_cli.py create-superuser \
   --user-id dan --display-name dan --password-stdin < "$ABS/dan_password" >/dev/null) \
   && echo "user dan created (superuser)"
AUTH="Authorization: Token $(cat $SB/admin_token)"
for p in app-theme app-views app-nav app-shell app-files app-projects app-collab \
         app-notes app-tasks app-notify app-settings app-sites; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$AUTH" "$URL/packages/$p/install")
  echo "package $p: $code"
done
(umask 077
 curl -s -X POST -H "$AUTH" -H 'Content-Type: application/json' -d '{"name":"scroll-sandbox"}' \
   "$URL/identity/users/dan/api-keys" |
 python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""), end="")' > $SB/dan_api_key)
[[ -s $SB/dan_api_key ]] && echo "API key for dan minted (in $SB/dan_api_key)" || echo "!! API key mint failed"
