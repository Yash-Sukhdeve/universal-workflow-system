#!/usr/bin/env python3
"""
UWS Dashboard Server with Real-Time WebSocket Support
Provides REST API and WebSocket connections for live agent monitoring
"""

import http.server
import socketserver
import json
import subprocess
import os
import glob
import threading
import time
import asyncio
from datetime import datetime
from pathlib import Path

# Try to import websockets, fall back to polling-only mode if not available
try:
    import websockets
    import websockets.sync.server
    WEBSOCKET_AVAILABLE = True
except ImportError:
    WEBSOCKET_AVAILABLE = False
    print("Note: websockets not installed. Running in polling-only mode.")
    print("Install with: pip install websockets")

PORT = 8080
WS_PORT = 8081
DIRECTORY = "dashboard"
SCRIPTS_DIR = "scripts"
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# WebSocket clients
ws_clients = set()
ws_clients_lock = threading.Lock()

# Agent configuration
AGENT_CONFIG = {
    "researcher": {"icon": "🔬", "color": "#3498db"},
    "architect": {"icon": "🏗️", "color": "#9b59b6"},
    "implementer": {"icon": "💻", "color": "#2ecc71"},
    "experimenter": {"icon": "🧪", "color": "#e67e22"},
    "optimizer": {"icon": "⚡", "color": "#e74c3c"},
    "deployer": {"icon": "🚀", "color": "#1abc9c"},
    "documenter": {"icon": "📝", "color": "#f1c40f"},
}


def get_sessions():
    """Read all active agent sessions from sessions.yaml"""
    sessions_file = os.path.join(PROJECT_ROOT, ".workflow/agents/sessions.yaml")
    sessions = []

    if not os.path.exists(sessions_file):
        return sessions

    try:
        with open(sessions_file, 'r') as f:
            content = f.read()

        # Parse sessions (simple YAML parsing)
        in_sessions = False
        current_session = {}

        for line in content.split('\n'):
            if line.strip() == 'sessions:':
                in_sessions = True
                continue
            if line.strip() == 'history:' or line.strip() == 'config:':
                in_sessions = False
                if current_session:
                    sessions.append(current_session)
                    current_session = {}
                continue

            if in_sessions:
                if line.strip().startswith('- id:'):
                    if current_session:
                        sessions.append(current_session)
                    current_session = {'id': line.split(':', 1)[1].strip().strip('"')}
                elif ':' in line and current_session:
                    key = line.strip().split(':')[0].strip()
                    value = line.split(':', 1)[1].strip().strip('"')
                    if key == 'progress':
                        try:
                            value = int(value)
                        except:
                            value = 0
                    current_session[key] = value

        if current_session:
            sessions.append(current_session)

    except Exception as e:
        print(f"Error reading sessions: {e}")

    # Enrich with agent config
    for session in sessions:
        agent = session.get('agent', 'unknown')
        config = AGENT_CONFIG.get(agent, {"icon": "🤖", "color": "#888888"})
        session['icon'] = config['icon']
        session['color'] = config['color']

        # Calculate elapsed time
        if 'started_at' in session:
            try:
                started = datetime.fromisoformat(session['started_at'].replace('Z', '+00:00'))
                elapsed = datetime.now(started.tzinfo) - started
                session['elapsed_minutes'] = int(elapsed.total_seconds() / 60)
            except:
                session['elapsed_minutes'] = 0

    return sessions


def get_events():
    """Read recent events from events.json"""
    events_file = os.path.join(PROJECT_ROOT, ".workflow/agents/events.json")
    events = []

    if os.path.exists(events_file):
        try:
            with open(events_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            events.append(json.loads(line))
                        except:
                            continue
        except:
            pass

    return events[-20:]  # Last 20 events


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def log_message(self, format, *args):
        # Suppress default logging for cleaner output
        pass

    def do_GET(self):
        if self.path == '/api/data':
            self.send_json_response(self.get_dashboard_data())
        elif self.path == '/api/sessions':
            self.send_json_response({"sessions": get_sessions()})
        elif self.path == '/api/events':
            self.send_json_response({"events": get_events()})
        elif self.path == '/api/agents':
            self.send_json_response({"agents": AGENT_CONFIG})
        elif self.path == '/api/ws-info':
            self.send_json_response({
                "websocket_available": WEBSOCKET_AVAILABLE,
                "ws_port": WS_PORT if WEBSOCKET_AVAILABLE else None,
                "ws_url": f"ws://localhost:{WS_PORT}" if WEBSOCKET_AVAILABLE else None
            })
        else:
            super().do_GET()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        try:
            payload = json.loads(post_data.decode()) if post_data else {}
        except:
            payload = {}

        response = {}

        if self.path == '/api/approve':
            cl_id = payload.get('id')
            response = self.run_script(f"./{SCRIPTS_DIR}/review.sh", "approve", cl_id)
        elif self.path == '/api/reject':
            cl_id = payload.get('id')
            response = self.run_script(f"./{SCRIPTS_DIR}/review.sh", "reject", cl_id)
        elif self.path == '/api/move':
            ticket_id = payload.get('id')
            status = payload.get('status')
            response = self.run_script(f"./{SCRIPTS_DIR}/pm.sh", "move", ticket_id, status)
        elif self.path == '/api/sessions':
            # Create new session
            agent = payload.get('agent', 'unknown')
            task = payload.get('task', 'No task')
            response = self.run_script(
                f"./{SCRIPTS_DIR}/lib/session_manager.sh", "create", agent, task
            )
        elif self.path.startswith('/api/sessions/') and '/progress' in self.path:
            # Update session progress
            session_id = self.path.split('/')[3]
            progress = payload.get('progress', 0)
            status = payload.get('status', 'active')
            response = self.run_script(
                f"./{SCRIPTS_DIR}/lib/session_manager.sh", "update",
                session_id, str(progress), status
            )
        elif self.path.startswith('/api/sessions/') and '/end' in self.path:
            # End session
            session_id = self.path.split('/')[3]
            result = payload.get('result', 'success')
            response = self.run_script(
                f"./{SCRIPTS_DIR}/lib/session_manager.sh", "end", session_id, result
            )

        self.send_json_response(response)

    def send_json_response(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def run_script(self, script, *args):
        try:
            result = subprocess.run(
                [script] + [a for a in args if a],
                capture_output=True,
                text=True,
                check=False,
                cwd=PROJECT_ROOT
            )
            return {
                "success": result.returncode == 0,
                "output": result.stdout.strip(),
                "error": result.stderr.strip() if result.stderr else None
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    def get_dashboard_data(self):
        # 1. Get CRs (Inbox)
        crs = []
        staging_dir = os.path.join(PROJECT_ROOT, ".uws/crs")
        if os.path.exists(staging_dir):
            for cr_path in glob.glob(os.path.join(staging_dir, "CR-*")):
                try:
                    meta = {}
                    summary_file = os.path.join(cr_path, "summary.md")
                    if os.path.exists(summary_file):
                        with open(summary_file, 'r') as f:
                            content = f.read()
                            for line in content.split('\n'):
                                if "**Agent**:" in line:
                                    meta['agent'] = line.split(':', 1)[1].strip()
                                if "**Ticket**:" in line:
                                    meta['ticket'] = line.split(':', 1)[1].strip()
                                if "**Date**:" in line:
                                    meta['date'] = ':'.join(line.split(':')[1:]).strip()

                    crs.append({
                        "id": os.path.basename(cr_path),
                        "agent": meta.get('agent', 'Unknown'),
                        "ticket": meta.get('ticket', 'None'),
                        "date": meta.get('date', ''),
                        "summary_path": f".uws/crs/{os.path.basename(cr_path)}/summary.md"
                    })
                except Exception:
                    continue

        # 2. Get Issues (Board)
        issues = []
        issues_dir = os.path.join(PROJECT_ROOT, ".uws/issues")
        if os.path.exists(issues_dir):
            for issue_file in glob.glob(os.path.join(issues_dir, "*.md")):
                try:
                    with open(issue_file, 'r') as f:
                        content = f.read()
                        meta = {}
                        for line in content.split('\n'):
                            if line.startswith("id:"):
                                meta['id'] = line.split(':', 1)[1].strip()
                            if line.startswith("title:"):
                                meta['title'] = line.split(':', 1)[1].strip()
                            if line.startswith("status:"):
                                meta['status'] = line.split(':', 1)[1].strip()
                            if line.startswith("type:"):
                                meta['type'] = line.split(':', 1)[1].strip()

                        if 'id' in meta:
                            issues.append(meta)
                except Exception:
                    continue

        # 3. Get Active Agent (legacy single-agent support)
        agent = "None"
        agent_file = os.path.join(PROJECT_ROOT, ".workflow/agents/active.yaml")
        if os.path.exists(agent_file):
            with open(agent_file, 'r') as f:
                for line in f:
                    if "current_agent:" in line:
                        agent = line.split(':')[1].strip().strip('"')
                        break

        # 4. Get All Active Sessions (new multi-agent support)
        sessions = get_sessions()

        return {
            "inbox": crs,
            "board": issues,
            "sessions": sessions,
            "system": {
                "active_agent": agent,
                "active_session_count": len(sessions),
                "status": "Healthy",
                "websocket_available": WEBSOCKET_AVAILABLE
            }
        }


# WebSocket server for real-time updates
last_event_count = 0


def broadcast_to_clients(message):
    """Send message to all connected WebSocket clients"""
    with ws_clients_lock:
        disconnected = set()
        for client in ws_clients:
            try:
                client.send(json.dumps(message))
            except:
                disconnected.add(client)
        ws_clients -= disconnected


def watch_events():
    """Watch events file for changes and broadcast to clients"""
    global last_event_count
    events_file = os.path.join(PROJECT_ROOT, ".workflow/agents/events.json")

    while True:
        try:
            if os.path.exists(events_file):
                events = get_events()
                if len(events) > last_event_count:
                    # New events - broadcast them
                    new_events = events[last_event_count:]
                    for event in new_events:
                        broadcast_to_clients(event)
                    last_event_count = len(events)
            time.sleep(0.5)  # Check every 500ms
        except Exception as e:
            print(f"Event watcher error: {e}")
            time.sleep(1)


def handle_websocket(websocket):
    """Handle individual WebSocket connection"""
    with ws_clients_lock:
        ws_clients.add(websocket)
    print(f"WebSocket client connected. Total: {len(ws_clients)}")

    try:
        # Send initial state
        sessions = get_sessions()
        websocket.send(json.dumps({
            "event": "initial_state",
            "data": {"sessions": sessions}
        }))

        # Keep connection alive and handle messages
        for message in websocket:
            try:
                data = json.loads(message)
                if data.get('action') == 'ping':
                    websocket.send(json.dumps({"event": "pong"}))
                elif data.get('action') == 'get_sessions':
                    websocket.send(json.dumps({
                        "event": "sessions_update",
                        "data": {"sessions": get_sessions()}
                    }))
            except:
                pass
    except:
        pass
    finally:
        with ws_clients_lock:
            ws_clients.discard(websocket)
        print(f"WebSocket client disconnected. Total: {len(ws_clients)}")


def run_websocket_server():
    """Run WebSocket server in separate thread"""
    if not WEBSOCKET_AVAILABLE:
        return

    try:
        with websockets.sync.server.serve(handle_websocket, "localhost", WS_PORT) as server:
            print(f"WebSocket server running on ws://localhost:{WS_PORT}")
            server.serve_forever()
    except Exception as e:
        print(f"WebSocket server error: {e}")


def main():
    print("=" * 60)
    print("  UWS Dashboard Server - Real-Time Agent Monitoring")
    print("=" * 60)
    print(f"  HTTP Server:     http://localhost:{PORT}")

    if WEBSOCKET_AVAILABLE:
        print(f"  WebSocket:       ws://localhost:{WS_PORT}")

        # Start event watcher thread
        event_thread = threading.Thread(target=watch_events, daemon=True)
        event_thread.start()

        # Start WebSocket server thread
        ws_thread = threading.Thread(target=run_websocket_server, daemon=True)
        ws_thread.start()
    else:
        print("  WebSocket:       Not available (install websockets)")

    print("=" * 60)
    print("  Press Ctrl+C to stop")
    print("=" * 60)

    # Start HTTP server
    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down...")


if __name__ == "__main__":
    main()
