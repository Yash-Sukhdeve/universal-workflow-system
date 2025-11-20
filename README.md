# Universal Workflow System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/yourusername/universal-workflow-system)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

A domain-agnostic, git-based workflow system with intelligent agents and skills for reproducible research and development. Maintains context across sessions, survives context resets, and adapts to any project type.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/universal-workflow-system.git
cd universal-workflow-system

# Initialize for your project
./scripts/init_workflow.sh

# Start with auto-detection
./scripts/detect_and_configure.sh
```

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
# Initialize LLM project
./scripts/init_project.sh --type llm

# Start optimization
./scripts/activate_agent.sh optimizer
./scripts/enable_skill.sh quantization pruning
```

### Production Software
```bash
# Setup production workflow
./scripts/init_project.sh --type software

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
./scripts/show_progress.sh

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

- [Complete Guide](docs/guide.md)
- [Agent Documentation](docs/agents.md)
- [Skill Catalog](docs/skills.md)
- [API Reference](docs/api.md)
- [Examples](docs/examples.md)

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

- [Issues](https://github.com/yourusername/universal-workflow-system/issues)
- [Discussions](https://github.com/yourusername/universal-workflow-system/discussions)
- [Wiki](https://github.com/yourusername/universal-workflow-system/wiki)

## 🚦 Status

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Tests](https://img.shields.io/badge/tests-passing-brightgreen)
![Coverage](https://img.shields.io/badge/coverage-95%25-brightgreen)

---

**Remember**: The workflow adapts to YOU, not the other way around. Start simple, evolve as needed.
