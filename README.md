# Universal Workflow System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](#)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

A domain-agnostic, git-based workflow system with intelligent agents and skills for reproducible research and development. Maintains context across sessions, survives context resets, and adapts to any project type.

## 🚀 Quick Start

```bash
# Navigate to your project directory
cd your-project

# Copy workflow system scripts to your project
# (or clone into a separate directory and copy scripts/)

# Initialize for your project
./scripts/init_workflow.sh

# Or use auto-detection
./scripts/detect_and_configure.sh
```

## 🔌 Claude Code Integration (NEW!)

One-liner to add UWS to any project with full Claude Code integration:

```bash
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
```

**What you get:**
- **Auto context loading** - Claude knows your project state on session start
- **Auto checkpointing** - State saved before context window resets
- **Slash commands** - `/uws:status`, `/uws:checkpoint`, `/uws:recover`, `/uws:handoff`

**Usage:**
```bash
# Start Claude Code in your project
claude

# Check status
/uws:status

# Create checkpoint
/uws:checkpoint "Completed feature X"

# Prepare handoff before ending
/uws:handoff
```

📖 **[Full Getting Started Guide](claude-code-integration/GETTING_STARTED.md)**

---

## 📋 Features

- **Context Persistence**: State survives any context window reset
- **Multi-Agent System**: Specialized agents for different tasks
- **Skill Library**: Reusable skills across projects
- **Domain Agnostic**: Works for ML research, software development, LLM projects, etc.
- **Git Native**: Everything tracked in version control
- **Checkpoint System**: Clear progress markers and recovery points
- **Knowledge Accumulation**: Learns patterns across projects

## 🏗️ Architecture

```
your_project/
├── .workflow/          # Core workflow system
│   ├── state.yaml     # Current state
│   ├── agents/        # Agent definitions
│   ├── skills/        # Skill library
│   └── knowledge/     # Accumulated patterns
├── phases/            # Project phases
├── artifacts/         # Generated outputs
└── workspace/         # Working directory
```

## 🤖 Available Agents

| Agent | Purpose | Use Cases |
|-------|---------|-----------|
| **Researcher** | Literature review, hypothesis formation | Papers, surveys, analysis |
| **Architect** | System design, architecture planning | APIs, databases, pipelines |
| **Implementer** | Code development, model building | Prototypes, production code |
| **Experimenter** | Running experiments, benchmarks | A/B tests, ablations |
| **Optimizer** | Performance optimization | Quantization, pruning, tuning |
| **Deployer** | Deployment and DevOps | Cloud, edge, containers |
| **Documenter** | Documentation and papers | Technical docs, papers, guides |

## 🛠️ Skill Categories

### Research Skills
- Literature Review
- Experimental Design
- Statistical Validation
- Paper Writing

### ML/AI Skills
- Model Development
- Model Optimization (Quantization, Pruning)
- LLM Specialization
- Fine-tuning

### Software Engineering Skills
- Architecture Design
- Production Readiness
- Testing Suites
- CI/CD Pipelines

### Deployment Skills
- Containerization
- Cloud Deployment
- Monitoring Setup
- Scaling Strategies

## 📖 Usage Examples

### Research Project
```bash
# Activate research workflow
./scripts/activate_agent.sh researcher

# Enable relevant skills
./scripts/enable_skill.sh literature_review experimental_design

# Check current state
./scripts/status.sh
```

### LLM Development
```bash
# Initialize workflow and configure as LLM project
./scripts/init_workflow.sh
# (select option 4 for LLM/Transformer Project)

# Start optimization
./scripts/activate_agent.sh optimizer
./scripts/enable_skill.sh quantization pruning
```

### Production Software
```bash
# Setup production workflow
./scripts/init_workflow.sh
# (select option 3 for Software Development)

# Enable CI/CD
./scripts/enable_skill.sh ci_cd_setup deployment_pipeline
```

## 🔄 Context Recovery

Lost context? No problem:

```bash
# Recover full context
./scripts/recover_context.sh

# Shows:
# - Current phase and checkpoint
# - Active agents and skills
# - Next actions
# - Critical context
```

## 📊 Progress Tracking

```bash
# View current progress
./scripts/status.sh

# Verbose status with details
./scripts/status.sh --verbose

# Create checkpoint
./scripts/checkpoint.sh "Completed model training"

# View checkpoint history
cat .workflow/checkpoints.log
```

## 🧠 Knowledge System

The system learns from your patterns:

```yaml
# .workflow/knowledge/learned_patterns.yaml
- pattern: "LLM memory issues"
  solution: "Use gradient checkpointing"
  success_rate: 0.95
```

## 🔧 Configuration

### Project Types
- `research` - Academic research projects
- `software` - Production software development
- `llm` - LLM/transformer projects
- `optimization` - Model optimization work
- `deployment` - DevOps and deployment
- `hybrid` - Mixed projects

### Customization

Edit `.workflow/config.yaml` to customize:
- Default agents
- Skill preferences
- Checkpoint frequency
- Git integration settings

## 📚 Documentation

- [Agent Registry](.workflow/agents/registry.yaml) - Complete agent definitions and capabilities
- [Skill Catalog](.workflow/skills/catalog.yaml) - All available skills and chains
- [Workflow Examples](.workflow/templates/workflow_examples.yaml) - Template workflows
- [CLAUDE.md](CLAUDE.md) - Integration guide for Claude Code
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Adding New Skills

1. Create skill definition in `.workflow/skills/definitions/`
2. Add to skill catalog
3. Create execution logic
4. Submit PR with examples

### Adding New Agents

1. Define agent in `.workflow/agents/registry.yaml`
2. Create agent configuration
3. Add handoff protocols
4. Submit PR with use cases

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by reproducible research principles
- Built for researchers and developers who context-switch
- Designed for real-world, complex projects

## 📮 Support

For issues and questions:
- Review [CLAUDE.md](CLAUDE.md) for Claude Code integration
- Check [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines
- Examine workflow configuration files in `.workflow/` directory

## 🚦 Status

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Development](https://img.shields.io/badge/status-active-brightgreen)
![License](https://img.shields.io/badge/license-MIT-yellow)

---

**Remember**: The workflow adapts to YOU, not the other way around. Start simple, evolve as needed.
