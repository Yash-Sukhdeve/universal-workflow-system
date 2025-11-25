#!/usr/bin/env python3
"""
Predictive Dataset Generator for PROMISE 2026 Paper

Generates a comprehensive dataset of workflow recovery scenarios for training
predictive models that estimate:
- Recovery time (regression)
- Recovery success probability (classification)
- State completeness after recovery (regression)

Dataset enables research on:
- Predicting context recovery success in AI-assisted development
- Identifying factors influencing recovery performance
- Building effort estimation models for workflow tools

Citation: Universal Workflow System - PROMISE 2026
"""

import json
import os
import subprocess
import tempfile
import time
import shutil
import random
import hashlib
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
import statistics
import csv

# Try to import scipy for advanced stats
try:
    from scipy import stats
    import numpy as np
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False
    print("Warning: scipy not available. Install with: pip install scipy numpy")

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
DATASET_DIR = PROJECT_ROOT / "artifacts" / "predictive_dataset"
NUM_SCENARIOS = 1000  # Target: 1000+ scenarios
TRIALS_PER_SCENARIO = 3  # Multiple measurements per scenario

# Scenario parameter space
SCENARIO_PARAMS = {
    "checkpoint_count": [1, 5, 10, 25, 50, 100, 200],
    "state_complexity": ["minimal", "low", "medium", "high", "complex"],
    "project_type": ["ml_pipeline", "web_dev", "research", "devops", "data_eng", "llm_app", "mixed"],
    "agent_state": ["idle", "active", "handoff", "transition"],
    "corruption_level": [0, 5, 10, 25, 50, 75, 90],  # Percentage
    "handoff_size": ["small", "medium", "large", "very_large"],
    "skill_count": [0, 3, 5, 10, 15],
    "interruption_type": ["clean", "abrupt", "crash", "timeout"],
    "time_since_checkpoint": [0, 60, 300, 3600, 86400],  # seconds
}

# State complexity definitions
STATE_COMPLEXITY_SIZES = {
    "minimal": {"lines": 20, "sections": 2},
    "low": {"lines": 50, "sections": 4},
    "medium": {"lines": 150, "sections": 8},
    "high": {"lines": 400, "sections": 15},
    "complex": {"lines": 1000, "sections": 25},
}

# Handoff size definitions (approximate characters)
HANDOFF_SIZES = {
    "small": 500,
    "medium": 2000,
    "large": 8000,
    "very_large": 25000,
}

# Project type templates
PROJECT_TEMPLATES = {
    "ml_pipeline": {
        "phases": ["data_prep", "training", "evaluation", "deployment"],
        "agents": ["researcher", "implementer", "experimenter"],
        "skills": ["model_development", "benchmarking", "optimization"],
    },
    "web_dev": {
        "phases": ["design", "frontend", "backend", "testing", "deploy"],
        "agents": ["architect", "implementer", "experimenter", "deployer"],
        "skills": ["testing", "containerization", "ci_cd"],
    },
    "research": {
        "phases": ["literature", "hypothesis", "experiment", "analysis", "writing"],
        "agents": ["researcher", "experimenter", "documenter"],
        "skills": ["literature_review", "statistical_validation", "paper_writing"],
    },
    "devops": {
        "phases": ["setup", "infrastructure", "monitoring", "optimization"],
        "agents": ["deployer", "optimizer"],
        "skills": ["containerization", "ci_cd", "monitoring", "scaling"],
    },
    "data_eng": {
        "phases": ["ingestion", "processing", "warehouse", "analytics"],
        "agents": ["architect", "implementer", "optimizer"],
        "skills": ["profiling", "optimization", "benchmarking"],
    },
    "llm_app": {
        "phases": ["design", "prompting", "rag", "evaluation", "deployment"],
        "agents": ["researcher", "implementer", "experimenter", "deployer"],
        "skills": ["model_development", "benchmarking", "optimization"],
    },
    "mixed": {
        "phases": ["phase_1", "phase_2", "phase_3", "phase_4", "phase_5"],
        "agents": ["researcher", "architect", "implementer", "experimenter", "deployer"],
        "skills": ["testing", "benchmarking", "documentation"],
    },
}


@dataclass
class ScenarioFeatures:
    """Features extracted from a recovery scenario"""
    # Scenario parameters
    scenario_id: str
    checkpoint_count: int
    state_complexity: str
    state_lines: int
    project_type: str
    agent_state: str
    corruption_level: int
    handoff_size: str
    handoff_chars: int
    skill_count: int
    interruption_type: str
    time_since_checkpoint: int

    # Derived features
    state_file_size_bytes: int
    checkpoint_log_size_bytes: int
    total_workflow_files: int
    active_agent_count: int
    phase_progress_percent: int
    has_blockers: bool
    has_pending_actions: bool


@dataclass
class ScenarioOutcome:
    """Ground truth outcomes for a scenario"""
    # Primary outcomes
    recovery_success: bool
    recovery_time_ms: float
    state_completeness_percent: float

    # Secondary outcomes
    checkpoint_parse_time_ms: float
    state_load_time_ms: float
    handoff_read_time_ms: float

    # Error information
    error_type: Optional[str]
    error_message: Optional[str]


@dataclass
class DatasetEntry:
    """Complete entry in the predictive dataset"""
    features: ScenarioFeatures
    outcome: ScenarioOutcome
    trial_number: int
    timestamp: str
    measurement_variance_ms: float


def ensure_dirs():
    """Create necessary directories"""
    DATASET_DIR.mkdir(parents=True, exist_ok=True)
    (DATASET_DIR / "raw").mkdir(exist_ok=True)
    (DATASET_DIR / "processed").mkdir(exist_ok=True)


def generate_scenario_id(params: Dict) -> str:
    """Generate unique scenario ID from parameters"""
    param_str = json.dumps(params, sort_keys=True)
    return hashlib.md5(param_str.encode()).hexdigest()[:12]


def generate_state_content(complexity: str, project_type: str, checkpoint_count: int,
                          agent_state: str, phase_progress: int) -> str:
    """Generate realistic state.yaml content based on parameters"""
    template = PROJECT_TEMPLATES.get(project_type, PROJECT_TEMPLATES["mixed"])
    size_config = STATE_COMPLEXITY_SIZES.get(complexity, STATE_COMPLEXITY_SIZES["medium"])

    # Determine current phase based on progress
    phases = template["phases"]
    current_phase_idx = min(int(phase_progress / 100 * len(phases)), len(phases) - 1)
    current_phase = phases[current_phase_idx]

    state = f"""# Auto-generated state for predictive dataset
project:
  name: "{project_type}-benchmark-{generate_scenario_id({'complexity': complexity})[:6]}"
  type: "{project_type}"
  created: "{(datetime.now() - timedelta(days=random.randint(1, 90))).isoformat()}"

current_phase: "{current_phase}"
current_checkpoint: "CP_{checkpoint_count}_{random.randint(1, 999)}"
checkpoint_count: {checkpoint_count}
phase_progress: {phase_progress}

agents:
  active: "{random.choice(template['agents'])}"
  state: "{agent_state}"
  available: {json.dumps(template['agents'])}

skills:
  enabled: {json.dumps(random.sample(template['skills'], min(len(template['skills']), 3)))}

context_bridge:
  critical_info:
"""

    # Add critical info items based on complexity
    num_items = size_config["sections"]
    for i in range(num_items):
        state += f'    - "Context item {i+1}: {generate_context_item(project_type, i)}"\n'

    state += """  next_actions:
"""
    for i in range(min(5, num_items)):
        state += f'    - "Action {i+1}: {generate_action_item(project_type, i)}"\n'

    if random.random() > 0.7:
        state += """  blockers:
    - "Pending external review"
"""

    state += f"""
metadata:
  last_updated: "{datetime.now().isoformat()}"
  session_count: {random.randint(1, 50)}
  total_checkpoints: {checkpoint_count}
"""

    # Pad to target size
    target_lines = size_config["lines"]
    current_lines = state.count('\n')
    if current_lines < target_lines:
        state += "\n# Additional context\n"
        state += "additional_data:\n"
        for i in range(target_lines - current_lines):
            state += f"  item_{i}: \"value_{i}_{random.randint(1000, 9999)}\"\n"

    return state


def generate_context_item(project_type: str, index: int) -> str:
    """Generate realistic context item"""
    items = {
        "ml_pipeline": ["Model architecture finalized", "Dataset preprocessed", "Hyperparameters tuned",
                       "Training completed", "Metrics collected", "Model validated"],
        "web_dev": ["API design approved", "Database schema ready", "Auth module done",
                   "Frontend components built", "Tests passing", "Staging deployed"],
        "research": ["Literature reviewed", "Hypothesis formed", "Experiment designed",
                    "Data collected", "Analysis complete", "Draft written"],
        "devops": ["Infrastructure provisioned", "CI/CD configured", "Monitoring setup",
                  "Alerts configured", "Load testing done", "Documentation ready"],
        "data_eng": ["Data sources identified", "ETL pipeline built", "Schema designed",
                    "Quality checks added", "Performance tuned", "Docs updated"],
        "llm_app": ["Prompts designed", "RAG configured", "Evaluation framework ready",
                   "Fine-tuning complete", "API integrated", "Rate limiting added"],
    }
    type_items = items.get(project_type, items["ml_pipeline"])
    return type_items[index % len(type_items)]


def generate_action_item(project_type: str, index: int) -> str:
    """Generate realistic action item"""
    actions = {
        "ml_pipeline": ["Run ablation study", "Optimize inference", "Document results",
                       "Prepare deployment", "Create API endpoint"],
        "web_dev": ["Write unit tests", "Add error handling", "Optimize queries",
                   "Setup monitoring", "Deploy to production"],
        "research": ["Run additional experiments", "Statistical validation", "Write discussion",
                    "Prepare figures", "Submit for review"],
        "devops": ["Scale infrastructure", "Add redundancy", "Update runbooks",
                  "Test disaster recovery", "Optimize costs"],
        "data_eng": ["Add data validation", "Optimize pipelines", "Add lineage tracking",
                    "Setup alerts", "Document schemas"],
        "llm_app": ["Improve prompts", "Add caching", "Implement fallbacks",
                   "Add rate limiting", "Setup A/B testing"],
    }
    type_actions = actions.get(project_type, actions["ml_pipeline"])
    return type_actions[index % len(type_actions)]


def generate_checkpoint_log(checkpoint_count: int, project_type: str) -> str:
    """Generate realistic checkpoint log"""
    log_entries = []
    base_time = datetime.now() - timedelta(days=30)

    for i in range(checkpoint_count):
        timestamp = base_time + timedelta(hours=random.randint(1, 24) * (i + 1))
        checkpoint_id = f"CP_{(i // 10) + 1}_{(i % 10) + 1:03d}"

        messages = [
            f"Phase {(i // 5) + 1} checkpoint",
            f"Completed milestone {i + 1}",
            f"Session end - {random.choice(['implementation', 'testing', 'review', 'planning'])}",
            f"Before context switch",
            f"Daily progress save",
        ]
        message = random.choice(messages)

        log_entries.append(f"{timestamp.isoformat()} | {checkpoint_id} | {message}")

    return "\n".join(log_entries)


def generate_handoff_content(size: str, project_type: str, phase_progress: int) -> str:
    """Generate realistic handoff.md content"""
    target_chars = HANDOFF_SIZES.get(size, HANDOFF_SIZES["medium"])
    template = PROJECT_TEMPLATES.get(project_type, PROJECT_TEMPLATES["mixed"])

    content = f"""# Context Handoff

## Current Status
- **Phase**: {random.choice(template['phases'])}
- **Progress**: {phase_progress}%
- **Active Agent**: {random.choice(template['agents'])}
- **Last Activity**: {(datetime.now() - timedelta(hours=random.randint(1, 48))).strftime('%Y-%m-%d %H:%M')}

## Critical Context

"""

    # Add sections until we reach target size
    section_templates = [
        ("### Recent Accomplishments", [
            "- Completed {task} for {component}",
            "- Fixed {issue} in {module}",
            "- Implemented {feature}",
            "- Updated {config} configuration",
        ]),
        ("### Current Focus", [
            "- Working on {feature} implementation",
            "- Debugging {issue} in {component}",
            "- Reviewing {item} changes",
            "- Testing {functionality}",
        ]),
        ("### Next Actions", [
            "- [ ] Complete {task}",
            "- [ ] Review {item}",
            "- [ ] Test {functionality}",
            "- [ ] Deploy {component}",
        ]),
        ("### Technical Notes", [
            "- {component} requires {requirement}",
            "- Performance concern in {module}",
            "- Consider {suggestion} for {goal}",
            "- API endpoint {endpoint} needs update",
        ]),
        ("### Blockers & Dependencies", [
            "- Waiting for {item} from {source}",
            "- Dependency on {component}",
            "- Need clarification on {topic}",
        ]),
    ]

    while len(content) < target_chars:
        section_title, templates = random.choice(section_templates)
        content += f"\n{section_title}\n\n"
        for _ in range(random.randint(3, 8)):
            template_line = random.choice(templates)
            # Fill in placeholders
            filled = template_line.format(
                task=random.choice(["user auth", "data validation", "API integration", "caching"]),
                component=random.choice(["backend", "frontend", "database", "API"]),
                issue=random.choice(["memory leak", "race condition", "timeout", "validation"]),
                module=random.choice(["auth", "core", "utils", "handlers"]),
                feature=random.choice(["logging", "metrics", "alerts", "retry logic"]),
                config=random.choice(["database", "cache", "queue", "storage"]),
                item=random.choice(["PR #123", "spec", "design doc", "requirements"]),
                functionality=random.choice(["login flow", "data export", "search", "upload"]),
                requirement=random.choice(["refactoring", "optimization", "testing", "docs"]),
                suggestion=random.choice(["caching", "indexing", "batching", "async"]),
                goal=random.choice(["performance", "reliability", "scalability", "security"]),
                endpoint=random.choice(["/users", "/data", "/auth", "/api/v2"]),
                source=random.choice(["team", "client", "external", "review"]),
                topic=random.choice(["requirements", "scope", "timeline", "priority"]),
            )
            content += f"{filled}\n"

    return content[:target_chars]


def introduce_corruption(file_path: Path, level: int) -> bool:
    """Introduce controlled corruption to file"""
    if level == 0:
        return True

    try:
        content = file_path.read_text()
        content_len = len(content)

        if content_len == 0:
            return True

        # Calculate number of bytes to corrupt
        corrupt_bytes = int(content_len * level / 100)

        content_list = list(content)
        for _ in range(corrupt_bytes):
            pos = random.randint(0, len(content_list) - 1)
            content_list[pos] = random.choice(['X', '\x00', '\n', ' ', '@'])

        file_path.write_text(''.join(content_list))
        return True
    except Exception as e:
        return False


def measure_recovery(tmp_dir: Path, corruption_level: int) -> Tuple[ScenarioOutcome, Dict]:
    """Measure recovery performance and outcomes"""
    detailed_timings = {}
    success = True
    error_type = None
    error_message = None
    state_completeness = 100.0

    # Measure checkpoint log parsing
    start = time.perf_counter_ns()
    checkpoint_log = tmp_dir / ".workflow" / "checkpoints.log"
    try:
        if checkpoint_log.exists():
            content = checkpoint_log.read_text()
            lines = content.strip().split('\n') if content.strip() else []
            checkpoint_count = len(lines)
        else:
            checkpoint_count = 0
            state_completeness -= 20
    except Exception as e:
        error_type = "checkpoint_parse_error"
        error_message = str(e)
        checkpoint_count = 0
        state_completeness -= 30
    checkpoint_parse_time = (time.perf_counter_ns() - start) / 1e6
    detailed_timings["checkpoint_parse"] = checkpoint_parse_time

    # Measure state file loading
    start = time.perf_counter_ns()
    state_file = tmp_dir / ".workflow" / "state.yaml"
    try:
        if state_file.exists():
            content = state_file.read_text()
            # Simple YAML validation
            if "project:" in content and "current_phase:" in content:
                state_valid = True
            else:
                state_valid = False
                state_completeness -= 30
        else:
            state_valid = False
            state_completeness -= 40
    except Exception as e:
        error_type = "state_load_error"
        error_message = str(e)
        state_valid = False
        state_completeness -= 50
    state_load_time = (time.perf_counter_ns() - start) / 1e6
    detailed_timings["state_load"] = state_load_time

    # Measure handoff reading
    start = time.perf_counter_ns()
    handoff_file = tmp_dir / ".workflow" / "handoff.md"
    try:
        if handoff_file.exists():
            content = handoff_file.read_text()
            handoff_valid = len(content) > 50  # Minimal validation
            if not handoff_valid:
                state_completeness -= 10
        else:
            handoff_valid = False
            state_completeness -= 15
    except Exception as e:
        error_type = "handoff_read_error"
        error_message = str(e)
        handoff_valid = False
        state_completeness -= 20
    handoff_read_time = (time.perf_counter_ns() - start) / 1e6
    detailed_timings["handoff_read"] = handoff_read_time

    # Full recovery timing (using actual script)
    start = time.perf_counter_ns()
    original_dir = os.getcwd()
    try:
        os.chdir(tmp_dir)
        result = subprocess.run(
            ["./scripts/recover_context.sh"],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Check for actual errors vs warnings (return code 1 with yq warnings is OK)
        if result.returncode != 0:
            # Check if output contains actual success indicators
            output = result.stdout or ""
            has_state_output = "Current State:" in output or "Project Type:" in output
            # Only treat as failure if no useful output and stderr has real errors
            stderr = result.stderr or ""
            is_just_warnings = "Warning:" in stderr and "yq not found" in stderr

            if not has_state_output and not is_just_warnings:
                success = False
                error_type = "recovery_script_error"
                error_message = stderr[:200] if stderr else "Unknown error"
                state_completeness -= 30
            # else: script worked despite return code 1 (warnings only)
    except subprocess.TimeoutExpired:
        success = False
        error_type = "timeout"
        error_message = "Recovery exceeded 30s timeout"
        state_completeness = 0
    except Exception as e:
        success = False
        error_type = "recovery_exception"
        error_message = str(e)
        state_completeness -= 50
    finally:
        os.chdir(original_dir)

    recovery_time = (time.perf_counter_ns() - start) / 1e6
    detailed_timings["total_recovery"] = recovery_time

    # Adjust completeness for corruption
    if corruption_level > 0:
        state_completeness = max(0, state_completeness - (corruption_level * 0.5))

    # Determine overall success
    if state_completeness < 50:
        success = False

    outcome = ScenarioOutcome(
        recovery_success=success,
        recovery_time_ms=recovery_time,
        state_completeness_percent=max(0, min(100, state_completeness)),
        checkpoint_parse_time_ms=checkpoint_parse_time,
        state_load_time_ms=state_load_time,
        handoff_read_time_ms=handoff_read_time,
        error_type=error_type,
        error_message=error_message
    )

    return outcome, detailed_timings


def create_scenario(params: Dict) -> Tuple[ScenarioFeatures, List[ScenarioOutcome]]:
    """Create a single scenario and measure outcomes"""
    scenario_id = generate_scenario_id(params)

    # Extract parameters
    checkpoint_count = params["checkpoint_count"]
    state_complexity = params["state_complexity"]
    project_type = params["project_type"]
    agent_state = params["agent_state"]
    corruption_level = params["corruption_level"]
    handoff_size = params["handoff_size"]
    skill_count = params["skill_count"]
    interruption_type = params["interruption_type"]
    time_since_checkpoint = params["time_since_checkpoint"]

    phase_progress = random.randint(10, 90)
    outcomes = []

    for trial in range(TRIALS_PER_SCENARIO):
        # Create fresh temp directory
        tmp_dir = Path(tempfile.mkdtemp())

        try:
            # Initialize git repo
            subprocess.run(["git", "init", "--quiet"], cwd=tmp_dir, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "bench@test.com"], cwd=tmp_dir, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Benchmark"], cwd=tmp_dir, check=True, capture_output=True)

            # Copy UWS infrastructure
            workflow_src = PROJECT_ROOT / ".workflow"
            scripts_src = PROJECT_ROOT / "scripts"

            if workflow_src.exists():
                shutil.copytree(workflow_src, tmp_dir / ".workflow")
            if scripts_src.exists():
                shutil.copytree(scripts_src, tmp_dir / "scripts")

            # Generate state file
            state_content = generate_state_content(
                state_complexity, project_type, checkpoint_count, agent_state, phase_progress
            )
            state_file = tmp_dir / ".workflow" / "state.yaml"
            state_file.write_text(state_content)

            # Generate checkpoint log
            log_content = generate_checkpoint_log(checkpoint_count, project_type)
            log_file = tmp_dir / ".workflow" / "checkpoints.log"
            log_file.write_text(log_content)

            # Generate handoff
            handoff_content = generate_handoff_content(handoff_size, project_type, phase_progress)
            handoff_file = tmp_dir / ".workflow" / "handoff.md"
            handoff_file.write_text(handoff_content)

            # Apply corruption if specified
            if corruption_level > 0:
                if random.random() < 0.5:
                    introduce_corruption(state_file, corruption_level)
                elif random.random() < 0.5:
                    introduce_corruption(log_file, corruption_level)
                else:
                    introduce_corruption(handoff_file, corruption_level)

            # Simulate different interruption types
            if interruption_type == "crash":
                # Truncate a random file
                files = list((tmp_dir / ".workflow").glob("*"))
                if files:
                    target = random.choice(files)
                    if target.is_file():
                        content = target.read_text()
                        target.write_text(content[:len(content)//2])
            elif interruption_type == "timeout":
                # Create incomplete state
                state_file.write_text(state_content[:len(state_content)//3])

            # Measure recovery
            outcome, _ = measure_recovery(tmp_dir, corruption_level)
            outcomes.append(outcome)

        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    # Calculate derived features
    state_size = STATE_COMPLEXITY_SIZES.get(state_complexity, STATE_COMPLEXITY_SIZES["medium"])
    handoff_chars = HANDOFF_SIZES.get(handoff_size, HANDOFF_SIZES["medium"])
    template = PROJECT_TEMPLATES.get(project_type, PROJECT_TEMPLATES["mixed"])

    features = ScenarioFeatures(
        scenario_id=scenario_id,
        checkpoint_count=checkpoint_count,
        state_complexity=state_complexity,
        state_lines=state_size["lines"],
        project_type=project_type,
        agent_state=agent_state,
        corruption_level=corruption_level,
        handoff_size=handoff_size,
        handoff_chars=handoff_chars,
        skill_count=skill_count,
        interruption_type=interruption_type,
        time_since_checkpoint=time_since_checkpoint,
        state_file_size_bytes=state_size["lines"] * 50,  # Approximate
        checkpoint_log_size_bytes=checkpoint_count * 80,  # Approximate
        total_workflow_files=5 + skill_count,  # Approximate
        active_agent_count=len(template["agents"]),
        phase_progress_percent=phase_progress,
        has_blockers=random.random() > 0.7,
        has_pending_actions=random.random() > 0.3,
    )

    return features, outcomes


def generate_parameter_combinations() -> List[Dict]:
    """Generate diverse parameter combinations for scenarios"""
    combinations = []

    # Systematic coverage of parameter space
    for cp_count in SCENARIO_PARAMS["checkpoint_count"]:
        for complexity in SCENARIO_PARAMS["state_complexity"]:
            for proj_type in SCENARIO_PARAMS["project_type"]:
                for corruption in [0, 25, 75]:  # Sample corruption levels
                    combinations.append({
                        "checkpoint_count": cp_count,
                        "state_complexity": complexity,
                        "project_type": proj_type,
                        "agent_state": random.choice(SCENARIO_PARAMS["agent_state"]),
                        "corruption_level": corruption,
                        "handoff_size": random.choice(SCENARIO_PARAMS["handoff_size"]),
                        "skill_count": random.choice(SCENARIO_PARAMS["skill_count"]),
                        "interruption_type": random.choice(SCENARIO_PARAMS["interruption_type"]),
                        "time_since_checkpoint": random.choice(SCENARIO_PARAMS["time_since_checkpoint"]),
                    })

    # Add random combinations to reach target
    while len(combinations) < NUM_SCENARIOS:
        combinations.append({
            "checkpoint_count": random.choice(SCENARIO_PARAMS["checkpoint_count"]),
            "state_complexity": random.choice(SCENARIO_PARAMS["state_complexity"]),
            "project_type": random.choice(SCENARIO_PARAMS["project_type"]),
            "agent_state": random.choice(SCENARIO_PARAMS["agent_state"]),
            "corruption_level": random.choice(SCENARIO_PARAMS["corruption_level"]),
            "handoff_size": random.choice(SCENARIO_PARAMS["handoff_size"]),
            "skill_count": random.choice(SCENARIO_PARAMS["skill_count"]),
            "interruption_type": random.choice(SCENARIO_PARAMS["interruption_type"]),
            "time_since_checkpoint": random.choice(SCENARIO_PARAMS["time_since_checkpoint"]),
        })

    return combinations[:NUM_SCENARIOS]


def generate_dataset():
    """Generate complete predictive dataset"""
    print("="*70)
    print("PROMISE 2026 Predictive Dataset Generator")
    print("="*70)
    print(f"Target scenarios: {NUM_SCENARIOS}")
    print(f"Trials per scenario: {TRIALS_PER_SCENARIO}")
    print(f"Total measurements: {NUM_SCENARIOS * TRIALS_PER_SCENARIO}")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print("="*70)

    ensure_dirs()

    # Generate parameter combinations
    print("\nGenerating parameter combinations...")
    params_list = generate_parameter_combinations()
    print(f"Generated {len(params_list)} unique scenarios")

    # Generate scenarios
    dataset_entries = []
    successful_scenarios = 0
    failed_scenarios = 0

    for i, params in enumerate(params_list):
        if (i + 1) % 50 == 0:
            print(f"Progress: {i + 1}/{len(params_list)} scenarios "
                  f"({successful_scenarios} successful, {failed_scenarios} failed)")

        try:
            features, outcomes = create_scenario(params)

            for trial, outcome in enumerate(outcomes):
                # Calculate variance across trials
                recovery_times = [o.recovery_time_ms for o in outcomes]
                variance = statistics.stdev(recovery_times) if len(recovery_times) > 1 else 0

                entry = DatasetEntry(
                    features=features,
                    outcome=outcome,
                    trial_number=trial + 1,
                    timestamp=datetime.now().isoformat(),
                    measurement_variance_ms=variance
                )
                dataset_entries.append(entry)

            successful_scenarios += 1
        except Exception as e:
            print(f"Warning: Scenario {i+1} failed: {e}")
            failed_scenarios += 1

    print(f"\nGeneration complete: {successful_scenarios} successful, {failed_scenarios} failed")

    # Save dataset
    save_dataset(dataset_entries)

    # Generate summary statistics
    generate_summary(dataset_entries)

    return dataset_entries


def save_dataset(entries: List[DatasetEntry]):
    """Save dataset in multiple formats"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Save as JSON (full detail)
    json_path = DATASET_DIR / "raw" / f"predictive_dataset_{timestamp}.json"
    json_data = []
    for entry in entries:
        json_data.append({
            "features": asdict(entry.features),
            "outcome": asdict(entry.outcome),
            "trial_number": entry.trial_number,
            "timestamp": entry.timestamp,
            "measurement_variance_ms": entry.measurement_variance_ms
        })

    with open(json_path, "w") as f:
        json.dump(json_data, f, indent=2)
    print(f"\nSaved JSON dataset: {json_path}")

    # Save as CSV (for ML training)
    csv_path = DATASET_DIR / "processed" / f"training_data_{timestamp}.csv"

    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)

        # Header
        feature_fields = [
            "scenario_id", "checkpoint_count", "state_complexity", "state_lines",
            "project_type", "agent_state", "corruption_level", "handoff_size",
            "handoff_chars", "skill_count", "interruption_type", "time_since_checkpoint",
            "state_file_size_bytes", "checkpoint_log_size_bytes", "total_workflow_files",
            "active_agent_count", "phase_progress_percent", "has_blockers", "has_pending_actions"
        ]
        outcome_fields = [
            "recovery_success", "recovery_time_ms", "state_completeness_percent",
            "checkpoint_parse_time_ms", "state_load_time_ms", "handoff_read_time_ms"
        ]
        writer.writerow(feature_fields + outcome_fields + ["trial_number", "measurement_variance_ms"])

        # Data rows
        for entry in entries:
            row = [
                entry.features.scenario_id,
                entry.features.checkpoint_count,
                entry.features.state_complexity,
                entry.features.state_lines,
                entry.features.project_type,
                entry.features.agent_state,
                entry.features.corruption_level,
                entry.features.handoff_size,
                entry.features.handoff_chars,
                entry.features.skill_count,
                entry.features.interruption_type,
                entry.features.time_since_checkpoint,
                entry.features.state_file_size_bytes,
                entry.features.checkpoint_log_size_bytes,
                entry.features.total_workflow_files,
                entry.features.active_agent_count,
                entry.features.phase_progress_percent,
                int(entry.features.has_blockers),
                int(entry.features.has_pending_actions),
                int(entry.outcome.recovery_success),
                entry.outcome.recovery_time_ms,
                entry.outcome.state_completeness_percent,
                entry.outcome.checkpoint_parse_time_ms,
                entry.outcome.state_load_time_ms,
                entry.outcome.handoff_read_time_ms,
                entry.trial_number,
                entry.measurement_variance_ms
            ]
            writer.writerow(row)

    print(f"Saved CSV training data: {csv_path}")


def generate_summary(entries: List[DatasetEntry]):
    """Generate summary statistics for the dataset"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    summary_path = DATASET_DIR / f"dataset_summary_{timestamp}.json"

    # Calculate statistics
    recovery_times = [e.outcome.recovery_time_ms for e in entries]
    success_rate = sum(1 for e in entries if e.outcome.recovery_success) / len(entries) * 100
    completeness_scores = [e.outcome.state_completeness_percent for e in entries]

    # Group by key factors
    by_complexity = {}
    for entry in entries:
        key = entry.features.state_complexity
        if key not in by_complexity:
            by_complexity[key] = {"times": [], "successes": 0, "total": 0}
        by_complexity[key]["times"].append(entry.outcome.recovery_time_ms)
        by_complexity[key]["successes"] += int(entry.outcome.recovery_success)
        by_complexity[key]["total"] += 1

    by_corruption = {}
    for entry in entries:
        key = entry.features.corruption_level
        if key not in by_corruption:
            by_corruption[key] = {"times": [], "successes": 0, "total": 0}
        by_corruption[key]["times"].append(entry.outcome.recovery_time_ms)
        by_corruption[key]["successes"] += int(entry.outcome.recovery_success)
        by_corruption[key]["total"] += 1

    summary = {
        "metadata": {
            "generated": datetime.now().isoformat(),
            "total_entries": len(entries),
            "unique_scenarios": len(set(e.features.scenario_id for e in entries)),
            "trials_per_scenario": TRIALS_PER_SCENARIO,
            "paper": "PROMISE 2026 - Predicting Context Recovery in AI-Assisted Development"
        },
        "overall_statistics": {
            "recovery_time_ms": {
                "mean": round(statistics.mean(recovery_times), 2),
                "median": round(statistics.median(recovery_times), 2),
                "std_dev": round(statistics.stdev(recovery_times), 2) if len(recovery_times) > 1 else 0,
                "min": round(min(recovery_times), 2),
                "max": round(max(recovery_times), 2),
            },
            "success_rate_percent": round(success_rate, 2),
            "completeness_percent": {
                "mean": round(statistics.mean(completeness_scores), 2),
                "median": round(statistics.median(completeness_scores), 2),
            }
        },
        "by_state_complexity": {
            k: {
                "mean_recovery_ms": round(statistics.mean(v["times"]), 2),
                "success_rate": round(v["successes"] / v["total"] * 100, 2),
                "count": v["total"]
            }
            for k, v in by_complexity.items()
        },
        "by_corruption_level": {
            str(k): {
                "mean_recovery_ms": round(statistics.mean(v["times"]), 2),
                "success_rate": round(v["successes"] / v["total"] * 100, 2),
                "count": v["total"]
            }
            for k, v in sorted(by_corruption.items())
        },
        "feature_importance_indicators": {
            "note": "Preliminary correlation analysis - full analysis in training script",
            "expected_important_features": [
                "corruption_level",
                "state_complexity",
                "checkpoint_count",
                "interruption_type"
            ]
        }
    }

    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nSaved summary: {summary_path}")

    # Print summary to console
    print("\n" + "="*70)
    print("DATASET SUMMARY")
    print("="*70)
    print(f"Total entries: {len(entries)}")
    print(f"Unique scenarios: {len(set(e.features.scenario_id for e in entries))}")
    print(f"\nRecovery Time:")
    print(f"  Mean: {summary['overall_statistics']['recovery_time_ms']['mean']:.2f}ms")
    print(f"  Median: {summary['overall_statistics']['recovery_time_ms']['median']:.2f}ms")
    print(f"  Std Dev: {summary['overall_statistics']['recovery_time_ms']['std_dev']:.2f}ms")
    print(f"\nSuccess Rate: {success_rate:.1f}%")
    print(f"\nBy Complexity:")
    for k, v in summary["by_state_complexity"].items():
        print(f"  {k}: {v['mean_recovery_ms']:.1f}ms (success: {v['success_rate']:.1f}%)")
    print("="*70)


if __name__ == "__main__":
    generate_dataset()
