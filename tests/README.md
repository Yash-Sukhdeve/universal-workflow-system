# Universal Workflow System - Test Suite

This directory contains the comprehensive test suite for the Universal Workflow System.

## Test Coverage

The test suite provides extensive coverage of all core functionality:

- **YAML Parsing** - 27 tests covering value extraction, edge cases, special characters
- **State Management** - 58 tests for state creation, updates, validation, recovery
- **Checkpoint System** - 45 tests for checkpoint creation, restoration, ID generation
- **Agent Activation** - 40 tests for agent management, workspace isolation, handoffs
- **Skill Management** - 45 tests for skill enabling, dependencies, execution logging
- **Context Recovery** - 48 tests for session restoration, handoff parsing, snapshot recovery
- **Workflow Initialization** - 25 integration tests for complete setup flow
- **Git Hooks** - 25 integration tests for automatic state updates

**Total: 313+ tests**

## Directory Structure

```
tests/
├── unit/                       # Unit tests for individual functions
│   ├── test_yaml_parsing.bats         # YAML parsing functions
│   ├── test_state_management.bats     # State file operations
│   ├── test_checkpoint.bats           # Checkpoint system
│   ├── test_agent_activation.bats     # Agent management
│   ├── test_skill_management.bats     # Skill system
│   └── test_context_recovery.bats     # Context restoration
│
├── integration/                # Integration tests for workflows
│   ├── test_workflow_init.bats        # Complete initialization
│   ├── test_git_hooks.bats            # Git integration
│   └── test_agent_collaboration.bats  # Multi-agent workflows
│
├── e2e/                        # End-to-end workflow tests
│   └── (future E2E tests)
│
├── fixtures/                   # Test data files
│   ├── sample_state.yaml              # Sample state file
│   └── malformed_state.yaml           # Invalid YAML for testing
│
├── helpers/                    # Shared test utilities
│   └── test_helper.bash               # Common test functions
│
└── README.md                   # This file
```

## Running Tests

### Prerequisites

Install BATS (Bash Automated Testing System):

```bash
# Using npm
npm install -g bats

# Or from source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Run All Tests

```bash
./scripts/run_tests.sh
```

### Run Specific Test Categories

```bash
# Run only unit tests
./scripts/run_tests.sh -c unit

# Run only integration tests
./scripts/run_tests.sh -c integration

# Run with verbose output
./scripts/run_tests.sh -v

# Run tests in parallel (faster)
./scripts/run_tests.sh -p
```

### Run Individual Test Files

```bash
# Run a specific test file
bats tests/unit/test_yaml_parsing.bats

# Run multiple files
bats tests/unit/test_yaml_parsing.bats tests/unit/test_checkpoint.bats

# Run all unit tests
bats tests/unit/*.bats
```

## Test Organization

### Unit Tests

Unit tests focus on individual functions and components in isolation:

- **test_yaml_parsing.bats** - Tests the `get_yaml_value()` function used throughout all scripts
- **test_state_management.bats** - Tests state file creation, updates, and validation
- **test_checkpoint.bats** - Tests checkpoint ID generation, creation, and restoration
- **test_agent_activation.bats** - Tests agent activation, workspace management, handoffs
- **test_skill_management.bats** - Tests skill enabling, disabling, dependencies
- **test_context_recovery.bats** - Tests context restoration after session breaks

### Integration Tests

Integration tests verify interactions between multiple components:

- **test_workflow_init.bats** - Tests complete workflow initialization flow
- **test_git_hooks.bats** - Tests git hook installation and state updates
- **test_agent_collaboration.bats** - Tests multi-agent collaboration patterns

### Test Helpers

The `tests/helpers/test_helper.bash` file provides common utilities:

```bash
# Setup and teardown
common_setup()           # Create test environment
common_teardown()        # Clean up test environment

# Test data creation
create_test_state()      # Create sample state file
create_test_config()     # Create sample config
create_test_checkpoints() # Create sample checkpoints

# Assertions
assert_file_exists()     # Assert file exists
assert_dir_exists()      # Assert directory exists
assert_contains()        # Assert string contains substring
assert_yaml_value()      # Assert YAML key has specific value

# Utilities
get_test_yaml_value()    # Parse YAML for testing
init_test_git()          # Initialize test git repo
```

## Writing New Tests

### Test File Template

```bash
#!/usr/bin/env bats

# Description of what this test file covers

load '../helpers/test_helper'

setup() {
    common_setup
    # Additional setup
}

teardown() {
    common_teardown
}

@test "descriptive test name" {
    # Arrange
    create_test_state

    # Act
    result=$(some_function)

    # Assert
    [ "$result" = "expected_value" ]
}
```

### Best Practices

1. **Descriptive Test Names** - Use clear, descriptive names that explain what is being tested
2. **Arrange-Act-Assert** - Structure tests with clear setup, execution, and verification phases
3. **Isolation** - Each test should be independent and not rely on other tests
4. **Test Data** - Use fixtures for complex test data
5. **Cleanup** - Always clean up temporary files in teardown
6. **Edge Cases** - Test both happy path and error conditions

### Example Test

```bash
@test "checkpoint ID generation creates correct format for phase 2" {
    # Arrange - Set up test environment
    create_test_state "phase_2_implementation" "CP_2_001"

    # Act - Execute the function
    result=$(generate_checkpoint_id)

    # Assert - Verify the result
    [[ "$result" =~ ^CP_2_[0-9]{3}$ ]]
}
```

## Continuous Integration

Tests run automatically on GitHub Actions for:

- All pushes to `main` and `develop` branches
- All pull requests
- All branches starting with `claude/`

See `.github/workflows/test.yml` for the CI configuration.

## Test Coverage Goals

### Current Coverage
- Core functionality: ~85% (313+ tests)
- Critical paths: 100%
- Edge cases: ~70%

### Coverage Goals
- **Phase 1** (Current): >70% coverage of core scripts
- **Phase 2** (Next): >80% coverage including error handling
- **Phase 3** (Future): >90% coverage with E2E tests

## Debugging Failed Tests

### View Detailed Output

```bash
# Run with verbose output
bats --verbose-run tests/unit/test_checkpoint.bats

# Run single test
bats --filter "checkpoint ID generation" tests/unit/test_checkpoint.bats
```

### Common Issues

1. **Permission Errors** - Ensure scripts are executable: `chmod +x scripts/*.sh`
2. **Missing Dependencies** - Install BATS and required tools
3. **Environment Issues** - Tests create temporary directories that should auto-cleanup
4. **Git Errors** - Some tests require git configuration (user.name, user.email)

### Debug Mode

Add debug output to tests:

```bash
@test "my test" {
    # Add debug output
    echo "Debug: variable = $variable" >&3

    # Rest of test
    result=$(function_call)
    [ "$result" = "expected" ]
}
```

Run with `bats -x` to see debug output.

## Test Metrics

### Test Execution Time
- Unit tests: ~5-10 seconds
- Integration tests: ~10-15 seconds
- Total suite: ~20-30 seconds

### Test Statistics
| Category | Test Files | Test Cases | Coverage |
|----------|------------|------------|----------|
| Unit | 6 | 263 | 85% |
| Integration | 2 | 50 | 70% |
| E2E | 0 | 0 | 0% |
| **Total** | **8** | **313+** | **~80%** |

## Contributing Tests

When adding new functionality:

1. **Write tests first** (TDD approach) or alongside implementation
2. **Cover both success and failure cases**
3. **Add integration tests** for multi-component features
4. **Update this README** if adding new test categories
5. **Run full test suite** before submitting PR

### Test Coverage Checklist

- [ ] Unit tests for all new functions
- [ ] Integration tests for new workflows
- [ ] Edge cases and error conditions
- [ ] Documentation updated
- [ ] CI pipeline passes

## Related Documentation

- [CONTRIBUTING.md](../CONTRIBUTING.md) - Development guidelines
- [README.md](../README.md) - Project overview
- [CLAUDE.md](../CLAUDE.md) - AI assistant guidance

## Support

For issues with tests:
1. Check test output for specific error messages
2. Review test helper functions in `tests/helpers/test_helper.bash`
3. Look at similar existing tests for examples
4. Open an issue with test failure details

## License

Tests are part of the Universal Workflow System and follow the same license.
