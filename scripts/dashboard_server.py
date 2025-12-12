#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import os
import glob

PORT = 8080
DIRECTORY = "dashboard"
SCRIPTS_DIR = "scripts"

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        if self.path == '/api/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = self.get_dashboard_data()
            self.wfile.write(json.dumps(data).encode())
        else:
            super().do_GET()

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        payload = json.loads(post_data.decode())
        
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
            
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

    def run_script(self, script, *args):
        try:
            result = subprocess.run(
                [script] + list(args),
                capture_output=True,
                text=True,
                check=False
            )
            return {
                "success": result.returncode == 0,
                "output": result.stdout,
                "error": result.stderr
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    def get_dashboard_data(self):
        # 1. Get CRs (Inbox)
        crs = []
        staging_dir = ".uws/crs"
        if os.path.exists(staging_dir):
            for cr_path in glob.glob(os.path.join(staging_dir, "CR-*")):
                try:
                    meta = {}
                    with open(os.path.join(cr_path, "summary.md"), 'r') as f:
                        content = f.read()
                        # Simple parsing
                        for line in content.split('\n'):
                            if "**Agent**:" in line: meta['agent'] = line.split(':')[1].strip()
                            if "**Ticket**:" in line: meta['ticket'] = line.split(':')[1].strip()
                            if "**Date**:" in line: meta['date'] = line.split(':')[1].strip()
                    
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
        issues_dir = ".uws/issues"
        if os.path.exists(issues_dir):
            for issue_file in glob.glob(os.path.join(issues_dir, "*.md")):
                try:
                    with open(issue_file, 'r') as f:
                        # Parse frontmatter
                        content = f.read()
                        # Very basic yaml parsing assuming standard format
                        meta = {}
                        for line in content.split('\n'):
                            if line.startswith("id:"): meta['id'] = line.split(':', 1)[1].strip()
                            if line.startswith("title:"): meta['title'] = line.split(':', 1)[1].strip()
                            if line.startswith("status:"): meta['status'] = line.split(':', 1)[1].strip()
                            if line.startswith("type:"): meta['type'] = line.split(':', 1)[1].strip()
                        
                        if 'id' in meta: issues.append(meta)
                except Exception:
                    continue

        # 3. Get Active Agent
        agent = "Unknown"
        agent_file = ".workflow/agents/active.yaml"
        if os.path.exists(agent_file):
            with open(agent_file, 'r') as f:
                for line in f:
                    if "current_agent:" in line:
                        agent = line.split(':')[1].strip().strip('"')
                        break

        return {
            "inbox": crs,
            "board": issues,
            "system": {
                "active_agent": agent,
                "status": "Healthy"
            }
        }

print(f"Starting Dashboard UI at http://localhost:{PORT}")
with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
    httpd.serve_forever()
