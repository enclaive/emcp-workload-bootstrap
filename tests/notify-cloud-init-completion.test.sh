#!/usr/bin/env bash
# Behavioural test for scripts/lib/notify-cloud-init-completion.sh and
# scripts/lib/webhook-events.sh. Needs bash, curl and python3; no network.
#
#   bash tests/notify-cloud-init-completion.test.sh

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
notifier="$repo_root/scripts/lib/notify-cloud-init-completion.sh"
sender="$repo_root/scripts/lib/webhook-events.sh"

work="$(mktemp -d)"
server_pid=''
failures=0

cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2> /dev/null
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/cloud-init-dir"

# Stub cloud-init: exits with $STUB_CLOUD_INIT_EXIT.
cat > "$work/bin/cloud-init" << 'STUB'
#!/usr/bin/env bash
exit "${STUB_CLOUD_INIT_EXIT:-0}"
STUB
chmod +x "$work/bin/cloud-init"

# Fake webhook: answers 500 for the first $2 requests, then 200; logs "code body".
cat > "$work/server.py" << 'PY'
import http.server, sys

log, fail_first = sys.argv[1], int(sys.argv[2])
state = {'requests': 0}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        state['requests'] += 1
        code = 500 if state['requests'] <= fail_first else 200
        with open(log, 'a') as handle:
            handle.write(f'{code} {body}\n')
        self.send_response(code)
        self.end_headers()

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
PY

start_server() { # fail_first
  : > "$work/log"
  python3 "$work/server.py" "$work/log" "$1" > "$work/port" &
  server_pid=$!
  for _ in $(seq 1 50); do
    [ -s "$work/port" ] && return 0
    sleep 0.1
  done
  echo 'fake webhook did not start' >&2
  exit 1
}

stop_server() {
  kill "$server_pid" 2> /dev/null
  wait "$server_pid" 2> /dev/null
  server_pid=''
  rm -f "$work/port"
}

run_notifier() { # cloud_init_exit
  PATH="$work/bin:$PATH" \
    STUB_CLOUD_INIT_EXIT="$1" \
    WEBHOOK_URL="http://127.0.0.1:$(cat "$work/port")/hook" \
    ENCLAIVE_CLOUD_INIT_DIR="$work/cloud-init-dir" \
    WEBHOOK_MAX_RETRIES=3 WEBHOOK_RETRY_SLEEP_SECONDS=0 \
    bash "$notifier" > "$work/output" 2>&1
}

check() { # description expected actual
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    echo "     expected: $2"
    echo "     actual:   $3"
    failures=$((failures + 1))
  fi
}

install_hook() { # body
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$work/cloud-init-dir/pre-completion-hook.sh"
  chmod +x "$work/cloud-init-dir/pre-completion-hook.sh"
  rm -f "$work/hook-ran"
}

# --- notifier: outcome mapping -------------------------------------------------
rm -f "$work/cloud-init-dir/pre-completion-hook.sh"

start_server 0
run_notifier 0
check 'done -> cloud-init-completed' '200 {"type":"cloud-init-completed"}' "$(cat "$work/log")"
stop_server

start_server 0
run_notifier 2
check 'degraded -> cloud-init-completed with degraded flag' '200 {"type":"cloud-init-completed","degraded":true}' "$(cat "$work/log")"
stop_server

start_server 0
run_notifier 1
check 'error -> cloud-init-failed with exit code' '200 {"type":"cloud-init-failed","exitCode":1}' "$(cat "$work/log")"
stop_server

# --- notifier: pre-completion hook ---------------------------------------------
install_hook "touch '$work/hook-ran'"
start_server 0
run_notifier 0
check 'hook runs before a reported success' 'yes' "$([ -e "$work/hook-ran" ] && echo yes || echo no)"
stop_server

install_hook "touch '$work/hook-ran'"
start_server 0
run_notifier 1
check 'hook is skipped when cloud-init failed' 'no' "$([ -e "$work/hook-ran" ] && echo yes || echo no)"
stop_server

install_hook 'exit 1'
start_server 0
run_notifier 0
check 'a failing hook does not change the reported outcome' '200 {"type":"cloud-init-completed"}' "$(cat "$work/log")"
stop_server
rm -f "$work/cloud-init-dir/pre-completion-hook.sh"

# --- sender: retries and validation ---------------------------------------------
start_server 2
run_notifier 0
check 'retries until the webhook answers 200' \
  "$(printf '500 {"type":"cloud-init-completed"}\n500 {"type":"cloud-init-completed"}\n200 {"type":"cloud-init-completed"}')" \
  "$(cat "$work/log")"
stop_server

start_server 99
run_notifier 0
status=$?
check 'gives up after the retry budget' '3' "$(wc -l < "$work/log" | tr -d ' ')"
check 'exits with status 1 when the webhook never answers 200' '1' "$status"
stop_server

env -u WEBHOOK_URL PATH="$work/bin:$PATH" bash "$notifier" > "$work/output" 2>&1
status=$?
check 'requires WEBHOOK_URL (exit status)' '1' "$status"
check 'requires WEBHOOK_URL (message)' 'yes' "$(grep -q 'WEBHOOK_URL must be set' "$work/output" && echo yes || echo no)"

WEBHOOK_URL='http://127.0.0.1:1/' bash "$sender" cloud_init_failed_event '1;rm' > "$work/output" 2>&1
check 'rejects a non-numeric exit code' '2' "$?"

WEBHOOK_URL='http://127.0.0.1:1/' bash "$sender" installation_completed_event > "$work/output" 2>&1
check 'rejects an unknown event type' '2' "$?"

echo
if [ "$failures" -eq 0 ]; then
  echo 'All tests passed.'
else
  echo "$failures test(s) failed."
  exit 1
fi
