# Contributing to Universal Workflow System

Thank you for your interest in contributing to the Universal Workflow System! This document provides guidelines and instructions for contributing.

## 🤝 Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for all contributors.

## 🚀 Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/universal-workflow-system.git`
3. Create a new branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes
6. Commit with a descriptive message: `git commit -m "[FEATURE] Add new skill for X"`
7. Push to your fork: `git push origin feature/your-feature-name`
8. Create a Pull Request

## 📝 Contribution Types

### Adding New Agents

1. Define agent in `.workflow/agents/registry.yaml`
2. Create agent configuration template
3. Add handoff protocols
4. Document capabilities and use cases
5. Submit PR with example usage

Example structure:
```yaml
new_agent:
  name: "Your Agent Name"
  description: "What this agent does"
  capabilities:
    - capability_1
    - capability_2
  primary_skills:
    - skill_1
    - skill_2
```

### Adding New Skills

1. Create skill definition in `.workflow/skills/definitions/`
2. Add to skill catalog (`.workflow/skills/catalog.yaml`)
3. Create execution logic if needed
4. Add tests and documentation
5. Submit PR with examples

Example skill definition:
```yaml
skill_name:
  category: category_name
  description: "What this skill does"
  inputs:
    - input_1
    - input_2
  outputs:
    - output_1
    - output_2
  tools:
    - tool_1
    - tool_2
```

### Improving Documentation

- Fix typos or clarify existing documentation
- Add examples and use cases
- Create tutorials
- Improve README sections
- Add diagrams or visualizations

### Bug Fixes

1. Create an issue describing the bug
2. Reference the issue in your PR
3. Include tests that demonstrate the fix
4. Update documentation if needed

## 🎯 Pull Request Guidelines

### PR Title Format

Use these prefixes:
- `[FEATURE]` - New feature
- `[FIX]` - Bug fix
- `[DOCS]` - Documentation changes
- `[REFACTOR]` - Code refactoring
- `[TEST]` - Test additions or fixes
- `[AGENT]` - New agent or agent modifications
- `[SKILL]` - New skill or skill modifications

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tests pass locally
- [ ] New tests added (if applicable)
- [ ] Documentation updated

## Related Issues
Closes #XXX

## Screenshots (if applicable)
Add screenshots here
```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
./tests/run_all_tests.sh

# Test specific component
bats tests/unit/test_activate_agent.bats
bats tests/unit/test_enable_skill.bats
```

### Writing Tests

1. Create test files in `tests/` directory
2. Follow naming convention: `test_[component].py`
3. Include both unit and integration tests
4. Test edge cases and error handling

## 📁 Project Structure

```
universal-workflow-system/
├── .workflow/          # Core workflow system
│   ├── agents/        # Agent definitions
│   ├── skills/        # Skill library
│   └── knowledge/     # Knowledge base
├── scripts/           # Utility scripts
├── docs/             # Documentation
├── tests/            # Test files
└── docs/             # Documentation & tutorials
```

## 🎨 Code Style

### Shell Scripts
- Use bash shebang: `#!/bin/bash`
- Include error handling: `set -e`
- Add comments for complex logic
- Use meaningful variable names
- Follow shellcheck recommendations

### YAML Files
- Use 2 spaces for indentation
- Add comments for complex structures
- Keep consistent formatting
- Validate YAML syntax

### Python Code (if applicable)
- Follow PEP 8
- Use type hints
- Add docstrings
- Run black formatter

## 📚 Documentation Standards

### Inline Documentation
- Comment complex logic
- Explain non-obvious decisions
- Document assumptions

### README Updates
- Keep examples current
- Update feature list
- Maintain compatibility notes

### Skill Documentation
Include:
- Purpose and use cases
- Required inputs/outputs
- Dependencies
- Example usage
- Performance considerations

## 🔄 Workflow Integration

When adding features, ensure they:
1. Maintain context persistence
2. Support checkpoint/recovery
3. Work with existing agents/skills
4. Follow the phase system
5. Update state management properly

## 🏷️ Versioning

We use semantic versioning (MAJOR.MINOR.PATCH):
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes

## 💡 Feature Requests

1. Check existing issues first
2. Create detailed issue with:
   - Use case description
   - Expected behavior
   - Example workflow
   - Potential implementation

## 🐛 Bug Reports

Include:
- System information
- Steps to reproduce
- Expected vs actual behavior
- Error messages/logs
- Workflow state (if applicable)

## 📊 Performance Contributions

When optimizing:
- Include benchmarks
- Document performance improvements
- Ensure backward compatibility
- Test on various project types

## 🌐 Community

- **Discussions**: Use GitHub Discussions for questions
- **Issues**: Report bugs or request features
- **Wiki**: Contribute to documentation
- **Examples**: Share your workflows

## ✅ Checklist Before Submitting

- [ ] Code follows style guidelines
- [ ] Tests pass locally
- [ ] Documentation updated
- [ ] Commit messages are descriptive
- [ ] PR description filled out
- [ ] No conflicts with main branch
- [ ] Examples work correctly

## 🙏 Recognition

Contributors will be:
- Listed in [CONTRIBUTORS.md](CONTRIBUTORS.md)
- Mentioned in release notes
- Given credit in documentation

## 📮 Questions?

- Open a discussion
- Contact maintainers
- Check the wiki

Thank you for contributing to make the Universal Workflow System better! 🎉
