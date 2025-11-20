# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Universal Workflow System is a domain-agnostic, git-based workflow system with intelligent agents and skills for reproducible research and development. It maintains context across sessions, survives context resets, and adapts to any project type (ML research, LLM development, software engineering, etc.).

## Core Architecture

### State Management System
The workflow system is built around persistent state that survives context resets:
- `.workflow/state.yaml` - Core state file tracking current phase, checkpoint, and project type
- `.workflow/checkpoints.log` - Timestamped checkpoint history for recovery
- `.workflow/handoff.md` - Context handoff document for session continuity

### Multi-Agent System
Seven specialized agents handle different task types (defined in `.workflow/agents/registry.yaml`):
- **researcher**: Literature review, hypothesis formation, experimental design
- **architect**: System design, API design, architecture planning
- **implementer**: Code development, model building, prototypes
- **experimenter**: Running experiments, benchmarks, validation tests
- **optimizer**: Performance optimization, quantization, pruning
- **deployer**: Deployment, DevOps, CI/CD, monitoring
- **documenter**: Documentation, paper writing, technical guides

Agents follow collaboration patterns and transition rules defined in the registry. Each agent has dedicated workspace directories and agent-specific skills.

### Skill Library
Skills are reusable capabilities (cataloged in `.workflow/skills/catalog.yaml`) organized into categories:
- research, development, ml_ai, optimization, deployment, documentation

Skills can be chained together for complex workflows (see `skill_chains` in catalog).

### Phase System
Projects progress through five phases:
1. phase_1_planning - Requirements, scope, design
2. phase_2_implementation - Code and model development
3. phase_3_validation - Testing, experiments, validation
4. phase_4_delivery - Deployment, documentation
5. phase_5_maintenance - Monitoring, support, updates

Each phase has deliverables and completion criteria defined in workflow examples.

## Common Commands

### Initialization and Setup
```bash
# Initialize workflow system for current project
./scripts/init_workflow.sh

# Detect project type and configure automatically
./scripts/detect_and_configure.sh
```

### Agent Management
```bash
# Activate an agent
./scripts/activate_agent.sh <agent_name>

# Available agents: researcher, architect, implementer, experimenter, optimizer, deployer, documenter
./scripts/activate_agent.sh researcher

# Check agent status
./scripts/activate_agent.sh <agent_name> status

# Deactivate agent
./scripts/activate_agent.sh <agent_name> deactivate

# Prepare handoff to another agent
./scripts/activate_agent.sh <agent_name> handoff
```

### Skills and Capabilities
```bash
# Enable specific skills
./scripts/enable_skill.sh <skill_name> [skill_name2...]

# Example: Enable optimization skills
./scripts/enable_skill.sh quantization pruning
```

### Context and Progress
```bash
# Recover context after session break or context loss
./scripts/recover_context.sh

# Show current workflow status
./scripts/status.sh

# Show detailed status with checkpoint history
./scripts/status.sh --verbose

# Show compact status
./scripts/status.sh --compact

# Create checkpoint
./scripts/checkpoint.sh "Completed model training"

# View checkpoint history
cat .workflow/checkpoints.log
```

### Project Types
When initializing, the system detects or prompts for project type:
- `research` - Academic research projects
- `ml` - ML/AI development
- `software` - Production software development
- `llm` - LLM/transformer projects
- `optimization` - Model optimization work
- `deployment` - DevOps and deployment
- `hybrid` - Mixed projects

## Development Workflow

### Starting Work
1. Run `./scripts/recover_context.sh` to restore context from previous session
2. Check `.workflow/handoff.md` for critical context and next actions
3. Activate appropriate agent for current phase using `./scripts/activate_agent.sh`
4. Review current phase status with `./scripts/status.sh`

### During Development
- State is automatically tracked in `.workflow/state.yaml`
- Create checkpoints at key milestones using `./scripts/checkpoint.sh`
- Agent workspaces are in `workspace/<agent_name>/`
- Artifacts go in `artifacts/` directory
- Phase-specific work goes in `phases/phase_N_<name>/`

### Context Handoff
When switching contexts or agents:
1. Update `.workflow/handoff.md` with current status and critical context
2. Use `./scripts/activate_agent.sh <current_agent> handoff` to prepare transition
3. Ensure checkpoint is created before long breaks
4. Next session starts with `./scripts/recover_context.sh`

### Git Integration
- Git hooks automatically update state timestamps on commit
- Pre-commit hook adds checkpoint entries for workflow changes
- Workflow patterns added to `.gitignore` (agent memory, temp files)
- State files are tracked in version control for reproducibility

## Key Files and Locations

### Core Configuration
- `.workflow/config.yaml` - Project-specific configuration (agents, skills, git settings)
- `.workflow/agents/registry.yaml` - Agent definitions and capabilities
- `.workflow/skills/catalog.yaml` - Complete skill library
- `.workflow/templates/workflow_examples.yaml` - Template workflows for different project types

### State Files
- `.workflow/state.yaml` - Current phase, checkpoint, and context
- `.workflow/agents/active.yaml` - Active agent configuration
- `.workflow/skills/enabled.yaml` - Currently enabled skills
- `.workflow/checkpoints.log` - Checkpoint history

### Knowledge Base
- `.workflow/knowledge/patterns.yaml` - Learned patterns and solutions
- `.workflow/agents/memory/` - Saved agent states
- `.workflow/agents/handoff_*.yaml` - Agent transition records

### Working Directories
- `workspace/<agent_name>/` - Agent-specific workspaces
- `phases/phase_N_<name>/` - Phase deliverables
- `artifacts/` - Generated outputs (models, reports, metrics)
- `archive/` - Historical artifacts

## Important Patterns

### Context Recovery
The system is designed to recover full context even after complete context window loss:
1. State file preserves phase, checkpoint, and metadata
2. Handoff document maintains critical context and next actions
3. Checkpoint log provides historical trail
4. Agent memory persists between sessions

### Agent Collaboration
Agents follow defined collaboration patterns:
- `research_to_implementation`: researcher → architect → implementer
- `full_ml_pipeline`: researcher → implementer → experimenter → optimizer → deployer
- `production_software`: architect → implementer → experimenter → deployer → documenter

Handoff artifacts are explicitly defined for each transition.

### Skill Chains
Complex workflows use skill chains defined in the catalog:
- `full_research_pipeline`: literature_review → experimental_design → model_development → statistical_validation → paper_writing
- `ml_optimization_pipeline`: profiling → quantization → pruning → benchmarking
- `production_deployment`: testing → containerization → ci_cd → monitoring → scaling

### Checkpoint Strategy
- Create checkpoints at phase boundaries
- Use descriptive checkpoint messages
- Format: `TIMESTAMP | CHECKPOINT_ID | DESCRIPTION`
- Checkpoint IDs follow pattern: `CP_<phase>_<number>`

## Testing and Validation

When running tests, validation, or experiments:
- Use the `experimenter` agent
- Enable relevant skills: `testing`, `benchmarking`, `statistical_validation`
- Results go in `artifacts/` with clear naming
- Update checkpoint after validation milestones

## Documentation Standards

When writing documentation or papers:
- Activate `documenter` agent
- Enable skills: `technical_writing`, `paper_writing`, `visualization`
- Use appropriate templates from `.workflow/templates/`
- Place outputs in phase-appropriate directories

## Notes for Claude Code

- Always check `.workflow/state.yaml` to understand current project context
- Use `./scripts/recover_context.sh` when continuing previous work
- Create checkpoints before and after major changes
- Update `.workflow/handoff.md` when work is interrupted
- Follow agent transition rules when switching between different task types
- Respect the phase system - deliverables should match current phase
- The workflow adapts to YOU - start simple, evolve as needed
