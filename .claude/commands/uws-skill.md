---
description: Enable/disable UWS skills for active agent
allowed-tools: Bash(./scripts/enable_skill.sh:*)
argument-hint: <skill> [enable|disable|list|status]
---

Manage workflow skills.

Skill categories:
- research: literature_review, experimental_design, statistical_validation
- development: code_generation, debugging, testing, refactoring
- ml_ai: model_development, fine_tuning, quantization, pruning
- optimization: profiling, benchmarking, hyperparameter_tuning
- deployment: containerization, ci_cd, monitoring, scaling
- documentation: technical_writing, paper_writing, visualization

Usage:
- Enable: `./scripts/enable_skill.sh <skill> enable`
- Disable: `./scripts/enable_skill.sh <skill> disable`
- List all: `./scripts/enable_skill.sh list`
- Status: `./scripts/enable_skill.sh <skill> status`

Execute based on $ARGUMENTS
