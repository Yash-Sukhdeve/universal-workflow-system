#!/usr/bin/env bats
# The review/PM dashboard (scripts/dashboard_server.py, scripts/start_dashboard.sh).
# Its POST endpoints approve and reject change requests and create sessions, so a web
# page open in the same browser must not be able to call them (CSRF), and its writes
# must land in the project it shows, not in the UWS installation.

load '../helpers/test_helper'

setup() {
    setup_test_environment
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
    PROJ="$(mktemp -d)"
    mkdir -p "$PROJ/.workflow/agents"
    printf 'project_type: "software"\ncurrent_phase: "phase_1_planning"\n' > "$PROJ/.workflow/state.yaml"
    PIDS=""
}

teardown() {
    local p
    for p in $PIDS; do
        kill "$p" 2>/dev/null || true
    done
    rm -rf "$PROJ"
    teardown_test_environment
}

free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# wait_http <port>: until the dashboard answers (at most ~10 s)
wait_http() {
    local i
    for i in $(seq 1 50); do
        if python3 -c 'import sys, urllib.request; urllib.request.urlopen("http://127.0.0.1:%s/api/agents" % sys.argv[1], timeout=1)' "$1" 2>/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

start_server() {
    PORT="$(free_port)"
    UWS_PROJECT_ROOT="$PROJ" UWS_DASHBOARD_PORT="$PORT" UWS_DASHBOARD_WS_PORT="$(free_port)" \
        python3 "${PROJECT_ROOT}/scripts/dashboard_server.py" >/dev/null 2>&1 3>&- &
    PIDS="$PIDS $!"
    wait_http "$PORT"
}

# req <method> <path> [header=value ...] [-- body]: prints "STATUS <code>", then headers
# and body, using http.client so the Host and Origin headers are exactly as given
req() {
    python3 - "$PORT" "$@" <<'PY'
import http.client, sys
port, method, path = sys.argv[1], sys.argv[2], sys.argv[3]
rest = sys.argv[4:]
body = None
if "--" in rest:
    i = rest.index("--")
    body, rest = rest[i + 1].encode(), rest[:i]
headers = dict(h.split("=", 1) for h in rest)
c = http.client.HTTPConnection("127.0.0.1", int(port), timeout=5)
c.putrequest(method, path, skip_host=True)
headers.setdefault("Host", "localhost:%s" % port)
for k, v in headers.items():
    c.putheader(k, v)
if body is not None:
    c.putheader("Content-Length", str(len(body)))
c.endheaders()
if body is not None:
    c.send(body)
r = c.getresponse()
print("STATUS", r.status)
for k, v in r.getheaders():
    print("%s: %s" % (k, v))
print()
print(r.read().decode())
PY
}

token() {
    req GET / | sed -n 's/.*<meta name="uws-token" content="\([^"]*\)".*/\1/p' | head -1
}

@test "dashboard: a cross-origin text/plain POST is refused and creates nothing" {
    start_server
    run req POST /api/sessions "Origin=https://evil.example" "Content-Type=text/plain" \
        -- '{"agent":"researcher","task":"created by a foreign origin"}'
    [[ "$output" == "STATUS 403"* ]] || false
    [[ "$output" != *"Access-Control-Allow-Origin"* ]] || false
    [ ! -f "$PROJ/.workflow/agents/sessions.yaml" ]
}

@test "dashboard: POSTs need the page's token and JSON, and then land in the project" {
    start_server
    local t
    t="$(token)"
    [ -n "$t" ]
    # same origin, JSON, but no token
    run req POST /api/sessions "Origin=http://localhost:${PORT}" "Content-Type=application/json" \
        -- '{"agent":"researcher","task":"t"}'
    [[ "$output" == "STATUS 403"* ]] || false
    # token, but not JSON
    run req POST /api/sessions "Origin=http://localhost:${PORT}" "Content-Type=text/plain" \
        "X-UWS-Token=${t}" -- '{"agent":"researcher","task":"t"}'
    [[ "$output" == "STATUS 415"* ]] || false
    # what the page sends
    run req POST /api/sessions "Origin=http://localhost:${PORT}" "Content-Type=application/json" \
        "X-UWS-Token=${t}" -- '{"agent":"researcher","task":"from the page"}'
    [[ "$output" == "STATUS 200"* ]] || false
    [[ "$output" == *'"success": true'* ]] || false
    grep -q 'task: "from the page"' "$PROJ/.workflow/agents/sessions.yaml"
    [ ! -f "${PROJECT_ROOT}/.workflow/agents/sessions.yaml" ] || \
        [ "$(grep -c 'from the page' "${PROJECT_ROOT}/.workflow/agents/sessions.yaml")" = "0" ]
}

@test "dashboard: API reads are not shared across origins, and a foreign Host is refused" {
    start_server
    run req GET /api/data "Origin=https://evil.example"
    [[ "$output" == "STATUS 200"* ]] || false
    [[ "$output" != *"Access-Control-Allow-Origin"* ]] || false
    # DNS rebinding: a page on evil.example resolving to 127.0.0.1
    run req GET /api/data "Host=evil.example:${PORT}"
    [[ "$output" == "STATUS 403"* ]] || false
    run req OPTIONS /api/approve "Origin=https://evil.example"
    [[ "$output" != *"Access-Control-Allow-Origin"* ]] || false
}

@test "session_manager.sh writes into the project WORKFLOW_DIR names, not the UWS install" {
    local had=false
    [ -f "${PROJECT_ROOT}/.workflow/agents/sessions.yaml" ] && had=true
    cd "$PROJ"
    run env WORKFLOW_DIR="$PROJ/.workflow" "${PROJECT_ROOT}/scripts/lib/session_manager.sh" create researcher "a task"
    [ "$status" -eq 0 ]
    grep -q 'task: "a task"' "$PROJ/.workflow/agents/sessions.yaml"
    [ -f "$PROJ/.workflow/agents/events.json" ]
    if [[ "$had" == "false" ]]; then
        [ ! -f "${PROJECT_ROOT}/.workflow/agents/sessions.yaml" ]
    fi
}

@test "start_dashboard.sh: starting one project's dashboard leaves another port's running" {
    local p1 p2 other
    p1="$(free_port)"; p2="$(free_port)"
    other="$(mktemp -d)"
    mkdir -p "$other/.workflow"
    printf 'project_type: "software"\n' > "$other/.workflow/state.yaml"
    # start_dashboard.sh execs the server, so $! is the server's PID; its per-port PID
    # file goes to TMPDIR, here the test's own directory
    cd "$PROJ"
    TMPDIR="$PROJ" UWS_DASHBOARD_PORT="$p1" UWS_DASHBOARD_WS_PORT="$(free_port)" \
        "${PROJECT_ROOT}/scripts/start_dashboard.sh" >/dev/null 2>&1 3>&- &
    local first=$!
    PIDS="$PIDS $first"
    wait_http "$p1"
    cd "$other"
    TMPDIR="$PROJ" UWS_DASHBOARD_PORT="$p2" UWS_DASHBOARD_WS_PORT="$(free_port)" \
        "${PROJECT_ROOT}/scripts/start_dashboard.sh" >/dev/null 2>&1 3>&- &
    PIDS="$PIDS $!"
    wait_http "$p2"
    # the first project's dashboard was left running
    kill -0 "$first"
    wait_http "$p1"
    # a restart on the same port replaces it
    cd "$PROJ"
    TMPDIR="$PROJ" UWS_DASHBOARD_PORT="$p1" UWS_DASHBOARD_WS_PORT="$(free_port)" \
        "${PROJECT_ROOT}/scripts/start_dashboard.sh" >/dev/null 2>&1 3>&- &
    PIDS="$PIDS $!"
    sleep 1
    wait_http "$p1"
    run kill -0 "$first"
    [ "$status" -ne 0 ]
    rm -rf "$other"
}
