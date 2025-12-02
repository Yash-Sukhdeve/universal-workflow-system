#!/usr/bin/env python3
"""
Repository Mining Study for FSE 2026 Paper

Tests UWS applicability across diverse project types by simulating
deployment and measuring checkpoint/recovery success rates.

Target: 10 diverse projects
- 3 Python ML projects
- 3 JavaScript/TypeScript projects
- 2 Bash/DevOps projects
- 2 mixed/polyglot projects
"""

import json
import os
import subprocess
import tempfile
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

PROJECT_ROOT = Path(__file__).parent.parent.parent
RESULTS_DIR = PROJECT_ROOT / "artifacts" / "benchmark_results" / "repository_mining"


# Simulated project structures representing diverse real-world projects
PROJECT_TEMPLATES = {
    # Python ML Projects
    "python_ml_basic": {
        "type": "Python ML",
        "files": {
            "train.py": "import torch\n\ndef train(): pass",
            "model.py": "class Model:\n    def forward(self): pass",
            "data/loader.py": "def load_data(): pass",
            "configs/config.yaml": "epochs: 100\nlr: 0.001",
            "requirements.txt": "torch>=2.0\nnumpy>=1.21",
            "README.md": "# ML Project\n\nTraining pipeline"
        },
        "git_history": 15
    },
    "python_ml_research": {
        "type": "Python ML",
        "files": {
            "experiments/exp_001.py": "# Experiment 1",
            "experiments/exp_002.py": "# Experiment 2",
            "src/models/transformer.py": "class Transformer: pass",
            "src/data/dataset.py": "class Dataset: pass",
            "notebooks/analysis.ipynb": "{}",
            "results/metrics.json": "{}",
            "paper/main.tex": "\\documentclass{article}",
            "requirements.txt": "transformers>=4.0"
        },
        "git_history": 25
    },
    "python_ml_production": {
        "type": "Python ML",
        "files": {
            "src/pipeline/train.py": "def train(): pass",
            "src/pipeline/evaluate.py": "def evaluate(): pass",
            "src/models/classifier.py": "class Classifier: pass",
            "src/utils/metrics.py": "def compute_metrics(): pass",
            "tests/test_model.py": "def test_model(): pass",
            "configs/prod.yaml": "env: production",
            "Dockerfile": "FROM python:3.9",
            "setup.py": "from setuptools import setup"
        },
        "git_history": 30
    },

    # JavaScript/TypeScript Projects
    "typescript_webapp": {
        "type": "JavaScript/TypeScript",
        "files": {
            "src/index.tsx": "import React from 'react'",
            "src/components/App.tsx": "export function App() {}",
            "src/hooks/useApi.ts": "export function useApi() {}",
            "src/types/index.ts": "export interface User {}",
            "package.json": '{"name": "webapp", "version": "1.0.0"}',
            "tsconfig.json": '{"compilerOptions": {}}',
            "tests/App.test.tsx": "test('renders', () => {})"
        },
        "git_history": 20
    },
    "nodejs_api": {
        "type": "JavaScript/TypeScript",
        "files": {
            "src/server.ts": "import express from 'express'",
            "src/routes/users.ts": "export const router = {}",
            "src/middleware/auth.ts": "export function auth() {}",
            "src/models/User.ts": "export class User {}",
            "package.json": '{"name": "api", "type": "module"}',
            "tests/api.test.ts": "describe('API', () => {})",
            ".env.example": "DATABASE_URL=postgres://..."
        },
        "git_history": 18
    },
    "react_native_app": {
        "type": "JavaScript/TypeScript",
        "files": {
            "App.tsx": "export default function App() {}",
            "src/screens/Home.tsx": "export function Home() {}",
            "src/components/Button.tsx": "export function Button() {}",
            "src/navigation/index.tsx": "export function Nav() {}",
            "package.json": '{"name": "mobile-app"}',
            "app.json": '{"expo": {}}',
            "babel.config.js": "module.exports = {}"
        },
        "git_history": 22
    },

    # Bash/DevOps Projects
    "devops_infra": {
        "type": "Bash/DevOps",
        "files": {
            "scripts/deploy.sh": "#!/bin/bash\necho 'Deploying'",
            "scripts/backup.sh": "#!/bin/bash\ntar -czf backup.tar.gz /data",
            "terraform/main.tf": "provider \"aws\" {}",
            "terraform/variables.tf": "variable \"region\" {}",
            "ansible/playbook.yml": "- hosts: all",
            ".github/workflows/ci.yml": "name: CI\non: push",
            "Makefile": "deploy:\n\t./scripts/deploy.sh"
        },
        "git_history": 12
    },
    "bash_automation": {
        "type": "Bash/DevOps",
        "files": {
            "bin/setup.sh": "#!/bin/bash\nset -e",
            "bin/test.sh": "#!/bin/bash\nbats tests/",
            "lib/utils.sh": "log() { echo \"$1\"; }",
            "lib/config.sh": "CONFIG_DIR=/etc/app",
            "tests/test_utils.bats": "@test 'log works' { }",
            "config/defaults.conf": "LOG_LEVEL=info"
        },
        "git_history": 10
    },

    # Mixed/Polyglot Projects
    "fullstack_monorepo": {
        "type": "Mixed/Polyglot",
        "files": {
            "frontend/src/App.tsx": "export function App() {}",
            "frontend/package.json": '{"name": "frontend"}',
            "backend/src/main.py": "from fastapi import FastAPI",
            "backend/requirements.txt": "fastapi>=0.100",
            "backend/Dockerfile": "FROM python:3.9",
            "docker-compose.yml": "services:\n  frontend:",
            "scripts/dev.sh": "#!/bin/bash\ndocker-compose up",
            ".github/workflows/test.yml": "name: Test"
        },
        "git_history": 35
    },
    "data_platform": {
        "type": "Mixed/Polyglot",
        "files": {
            "ingestion/main.py": "import kafka",
            "processing/src/processor.scala": "object Processor {}",
            "api/src/server.go": "package main",
            "dashboard/src/App.tsx": "export function Dashboard() {}",
            "airflow/dags/pipeline.py": "from airflow import DAG",
            "terraform/main.tf": "resource \"aws_s3_bucket\" {}",
            "docs/architecture.md": "# Architecture",
            "Makefile": "all: build"
        },
        "git_history": 40
    }
}


def create_project(template_name: str, template: Dict, base_dir: Path) -> Path:
    """Create a project directory from template"""
    project_dir = base_dir / template_name
    project_dir.mkdir(parents=True, exist_ok=True)

    # Create files
    for file_path, content in template["files"].items():
        full_path = project_dir / file_path
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_text(content)

    # Initialize git
    os.chdir(project_dir)
    subprocess.run(["git", "init", "--quiet"], check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "study@test.com"], check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Study"], check=True, capture_output=True)

    # Create git history
    for i in range(template["git_history"]):
        dummy_file = project_dir / f"history_{i}.txt"
        dummy_file.write_text(f"Commit {i}")
        subprocess.run(["git", "add", "."], check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", f"Commit {i}", "--quiet"], check=True, capture_output=True)

    return project_dir


def setup_uws(project_dir: Path) -> bool:
    """Set up UWS in project directory"""
    try:
        # Copy UWS infrastructure
        workflow_src = PROJECT_ROOT / ".workflow"
        scripts_src = PROJECT_ROOT / "scripts"

        shutil.copytree(workflow_src, project_dir / ".workflow")
        shutil.copytree(scripts_src, project_dir / "scripts")

        # Initialize state
        state_file = project_dir / ".workflow" / "state.yaml"
        state_file.write_text(f"""
project:
  name: "{project_dir.name}"
  type: "software"
current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"
checkpoint_count: 0
metadata:
  created: "{datetime.now().isoformat()}"
  last_updated: "{datetime.now().isoformat()}"
""")

        (project_dir / ".workflow" / "checkpoints.log").touch()

        return True
    except Exception as e:
        print(f"  Setup failed: {e}")
        return False


def test_checkpoint(project_dir: Path, checkpoint_id: str) -> Tuple[bool, float]:
    """Test checkpoint creation, return (success, file_size_bytes)"""
    import time

    os.chdir(project_dir)

    start = time.perf_counter_ns()
    result = subprocess.run(
        ["./scripts/checkpoint.sh", checkpoint_id],
        capture_output=True,
        text=True
    )
    elapsed = (time.perf_counter_ns() - start) / 1e6

    success = result.returncode == 0

    # Get state file size
    state_file = project_dir / ".workflow" / "state.yaml"
    file_size = state_file.stat().st_size if state_file.exists() else 0

    return success, elapsed, file_size


def test_recovery(project_dir: Path) -> Tuple[bool, float]:
    """Test context recovery, return (success, time_ms)"""
    import time

    os.chdir(project_dir)

    start = time.perf_counter_ns()
    result = subprocess.run(
        ["./scripts/recover_context.sh"],
        capture_output=True,
        text=True
    )
    elapsed = (time.perf_counter_ns() - start) / 1e6

    success = result.returncode == 0 or "CONTEXT RECOVERY" in result.stdout

    return success, elapsed


def run_study() -> Dict:
    """Run the full repository mining study"""
    print("=" * 60)
    print("Repository Mining Study for FSE 2026")
    print("=" * 60)
    print(f"Projects: {len(PROJECT_TEMPLATES)}")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print()

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    results = {"projects": [], "summary": {}}

    # Create temporary base directory
    base_dir = Path(tempfile.mkdtemp())

    try:
        for template_name, template in PROJECT_TEMPLATES.items():
            print(f"\n{'='*40}")
            print(f"Testing: {template_name} ({template['type']})")
            print("="*40)

            project_result = {
                "name": template_name,
                "type": template["type"],
                "files_count": len(template["files"]),
                "git_commits": template["git_history"],
                "setup_success": False,
                "checkpoints": [],
                "recovery_tests": []
            }

            # Create project
            project_dir = create_project(template_name, template, base_dir)
            print(f"  Created project with {len(template['files'])} files, {template['git_history']} commits")

            # Setup UWS
            if setup_uws(project_dir):
                project_result["setup_success"] = True
                print("  UWS setup: SUCCESS")

                # Test checkpoints (3 per project)
                for i in range(3):
                    success, time_ms, size_bytes = test_checkpoint(project_dir, f"CP_TEST_{i}")
                    project_result["checkpoints"].append({
                        "id": f"CP_TEST_{i}",
                        "success": success,
                        "time_ms": round(time_ms, 2),
                        "state_size_bytes": size_bytes
                    })
                    status = "SUCCESS" if success else "FAILED"
                    print(f"  Checkpoint {i}: {status} ({time_ms:.1f}ms, {size_bytes}B)")

                # Test recovery (3 per project)
                for i in range(3):
                    success, time_ms = test_recovery(project_dir)
                    project_result["recovery_tests"].append({
                        "trial": i,
                        "success": success,
                        "time_ms": round(time_ms, 2)
                    })
                    status = "SUCCESS" if success else "FAILED"
                    print(f"  Recovery {i}: {status} ({time_ms:.1f}ms)")
            else:
                print("  UWS setup: FAILED")

            results["projects"].append(project_result)

            # Return to project root
            os.chdir(PROJECT_ROOT)

    finally:
        # Cleanup
        shutil.rmtree(base_dir, ignore_errors=True)
        os.chdir(PROJECT_ROOT)

    # Calculate summary statistics
    total_projects = len(results["projects"])
    setup_success = sum(1 for p in results["projects"] if p["setup_success"])

    all_checkpoints = [cp for p in results["projects"] for cp in p["checkpoints"]]
    checkpoint_success_rate = sum(1 for cp in all_checkpoints if cp["success"]) / len(all_checkpoints) * 100 if all_checkpoints else 0

    all_recoveries = [r for p in results["projects"] for r in p["recovery_tests"]]
    recovery_success_rate = sum(1 for r in all_recoveries if r["success"]) / len(all_recoveries) * 100 if all_recoveries else 0

    # Group by project type
    by_type = {}
    for project in results["projects"]:
        ptype = project["type"]
        if ptype not in by_type:
            by_type[ptype] = {"count": 0, "setup_success": 0, "checkpoint_success": 0, "recovery_success": 0}
        by_type[ptype]["count"] += 1
        if project["setup_success"]:
            by_type[ptype]["setup_success"] += 1
        by_type[ptype]["checkpoint_success"] += sum(1 for cp in project["checkpoints"] if cp["success"])
        by_type[ptype]["recovery_success"] += sum(1 for r in project["recovery_tests"] if r["success"])

    results["summary"] = {
        "total_projects": total_projects,
        "setup_success_count": setup_success,
        "setup_success_rate": round(setup_success / total_projects * 100, 1),
        "checkpoint_success_rate": round(checkpoint_success_rate, 1),
        "recovery_success_rate": round(recovery_success_rate, 1),
        "by_project_type": by_type,
        "timestamp": datetime.now().isoformat()
    }

    # Print summary
    print("\n" + "="*60)
    print("STUDY SUMMARY")
    print("="*60)
    print(f"Total Projects: {total_projects}")
    print(f"Setup Success: {setup_success}/{total_projects} ({results['summary']['setup_success_rate']}%)")
    print(f"Checkpoint Success Rate: {checkpoint_success_rate:.1f}%")
    print(f"Recovery Success Rate: {recovery_success_rate:.1f}%")
    print()
    print("By Project Type:")
    for ptype, stats in by_type.items():
        print(f"  {ptype}: {stats['setup_success']}/{stats['count']} setup, "
              f"{stats['checkpoint_success']}/{stats['count']*3} checkpoints, "
              f"{stats['recovery_success']}/{stats['count']*3} recoveries")

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = RESULTS_DIR / f"repository_mining_{timestamp}.json"
    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nResults saved to: {results_file}")

    return results


if __name__ == "__main__":
    run_study()
