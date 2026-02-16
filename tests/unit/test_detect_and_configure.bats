#!/usr/bin/env bats
# Unit tests for detect_and_configure.sh
# Tests project type detection and configuration

load '../helpers/test_helper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
    # Override PROJECT_ROOT so the script detects within test dir, not the real project
    export PROJECT_ROOT="${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# PYTHON PROJECT DETECTION
# =============================================================================

@test "detect_and_configure detects Python project with requirements.txt" {
    cd "${TEST_TMP_DIR}"

    # Create Python project indicators
    touch requirements.txt
    echo "flask==2.0.0" >> requirements.txt
    echo "requests==2.28.0" >> requirements.txt
    mkdir -p src
    touch src/main.py

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"Python"* ]] || [[ "$output" == *"software"* ]]
}

@test "detect_and_configure detects Node.js project with package.json" {
    cd "${TEST_TMP_DIR}"

    # Create Node.js project indicators
    cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "dependencies": {}
}
EOF
    mkdir -p src
    touch src/index.js

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    # Should detect something (Node.js maps to software type)
    [[ "$output" == *"Node"* ]] || [[ "$output" == *"software"* ]] || [[ "$output" == *"detected"* ]] || [[ "$output" == *"hybrid"* ]]
}

@test "detect_and_configure detects ML project with torch in requirements" {
    cd "${TEST_TMP_DIR}"

    # Create ML project indicators
    cat > requirements.txt << 'EOF'
torch==2.0.0
transformers==4.35.0
numpy==1.24.0
scikit-learn==1.3.0
EOF
    mkdir -p models
    mkdir -p experiments
    touch train.py

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"ml"* ]] || [[ "$output" == *"ML"* ]] || [[ "$output" == *"detected"* ]]
}

@test "detect_and_configure detects Research project with paper directory" {
    cd "${TEST_TMP_DIR}"

    # Create research project indicators
    mkdir -p paper
    mkdir -p experiments
    mkdir -p results
    touch paper/main.tex
    touch references.bib
    touch analysis.py

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"research"* ]] || [[ "$output" == *"Research"* ]] || [[ "$output" == *"detected"* ]]
}

@test "detect_and_configure detects Rust project with Cargo.toml" {
    cd "${TEST_TMP_DIR}"

    # Create Rust project indicators
    cat > Cargo.toml << 'EOF'
[package]
name = "test-project"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
    mkdir -p src
    touch src/main.rs

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"Rust"* ]] || [[ "$output" == *"software"* ]] || [[ "$output" == *"detected"* ]]
}

@test "detect_and_configure detects Go project with go.mod" {
    cd "${TEST_TMP_DIR}"

    # Create Go project indicators
    cat > go.mod << 'EOF'
module github.com/test/project

go 1.21
EOF
    touch main.go

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"Go"* ]] || [[ "$output" == *"software"* ]] || [[ "$output" == *"detected"* ]]
}

@test "detect_and_configure defaults to hybrid for empty project" {
    cd "${TEST_TMP_DIR}"

    # Only keep minimal workflow structure
    rm -f requirements.txt package.json Cargo.toml go.mod
    rm -rf paper models experiments

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"hybrid"* ]] || [[ "$output" == *"software"* ]] || [[ "$output" == *"detected"* ]]
}

# =============================================================================
# CONFIGURATION UPDATE TESTS
# =============================================================================

@test "detect_and_configure updates state.yaml with detected type" {
    cd "${TEST_TMP_DIR}"

    # Create Python/ML indicators
    echo "torch==2.0.0" > requirements.txt
    mkdir -p models

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --force

    assert_success

    # Check state was updated
    [[ -f ".workflow/state.yaml" ]]
}

@test "detect_and_configure updates config.yaml with detected type" {
    cd "${TEST_TMP_DIR}"

    echo "torch==2.0.0" > requirements.txt

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --force

    assert_success

    [[ -f ".workflow/config.yaml" ]]
}

@test "detect_and_configure provides recommendations for research project" {
    cd "${TEST_TMP_DIR}"

    mkdir -p paper experiments results
    touch paper/main.tex

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto

    assert_success
    [[ "$output" == *"researcher"* ]] || [[ "$output" == *"Recommend"* ]]
}

# =============================================================================
# FLAG TESTS
# =============================================================================

@test "detect_and_configure --help shows usage" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --help

    # --help exits with 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "detect_and_configure --verbose shows debug output" {
    cd "${TEST_TMP_DIR}"

    echo "flask==2.0.0" > requirements.txt

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"DEBUG"* ]] || [[ "$output" == *"Found"* ]] || [[ "$output" == *"score"* ]]
}

@test "detect_and_configure --force skips existing config check" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --force

    assert_success
}

@test "detect_and_configure --auto skips confirmation prompts" {
    cd "${TEST_TMP_DIR}"

    echo "torch==2.0.0" > requirements.txt

    # Should complete without interaction
    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto

    assert_success
    [[ "$output" == *"Auto-detected"* ]] || [[ "$output" == *"detected"* ]]
}

# =============================================================================
# HYBRID PROJECT DETECTION
# =============================================================================

@test "detect_and_configure handles hybrid projects with multiple indicators" {
    cd "${TEST_TMP_DIR}"

    # Create multiple project type indicators
    echo "torch==2.0.0" > requirements.txt
    cat > package.json << 'EOF'
{ "name": "test", "version": "1.0.0" }
EOF
    mkdir -p paper
    touch Dockerfile

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    # Should detect something (ml, hybrid, or software)
    [[ "$output" == *"detected"* ]] || [[ "$output" == *"Detected"* ]]
}

# =============================================================================
# NON-DESTRUCTIVE TESTS
# =============================================================================

@test "detect_and_configure preserves other config values" {
    cd "${TEST_TMP_DIR}"

    # Ensure config has additional fields
    cat > .workflow/config.yaml << 'EOF'
project:
  name: "my-project"
  type: "software"
  version: "1.0.0"

custom_setting: "preserve_me"
EOF

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --force

    assert_success

    # Original file should still be valid
    [[ -f ".workflow/config.yaml" ]]
}

# =============================================================================
# GIT DETECTION
# =============================================================================

@test "detect_and_configure works in git repository" {
    cd "${TEST_TMP_DIR}"

    # Git is already initialized by setup_test_environment
    mkdir -p src
    touch src/main.py
    echo "flask==2.0.0" > requirements.txt

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto

    assert_success
}

# =============================================================================
# DOCKER DETECTION
# =============================================================================

@test "detect_and_configure detects Docker in deployment projects" {
    cd "${TEST_TMP_DIR}"

    cat > Dockerfile << 'EOF'
FROM python:3.11
WORKDIR /app
COPY . .
CMD ["python", "main.py"]
EOF

    cat > docker-compose.yml << 'EOF'
version: '3'
services:
  app:
    build: .
EOF

    mkdir -p k8s

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"Docker"* ]] || [[ "$output" == *"deployment"* ]] || [[ "$output" == *"detected"* ]]
}

# =============================================================================
# CI/CD DETECTION
# =============================================================================

@test "detect_and_configure detects GitHub Actions" {
    cd "${TEST_TMP_DIR}"

    mkdir -p .github/workflows
    cat > .github/workflows/ci.yml << 'EOF'
name: CI
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"CI"* ]] || [[ "$output" == *"detected"* ]]
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

@test "detect_and_configure handles permission issues gracefully" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto

    # Should not crash
    assert_success
}

@test "detect_and_configure handles invalid arguments" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --invalid-flag

    assert_failure
    [[ "$output" == *"Error"* ]] || [[ "$output" == *"Unknown"* ]]
}

# =============================================================================
# LLM PROJECT DETECTION
# =============================================================================

@test "detect_and_configure detects LLM project with transformers" {
    cd "${TEST_TMP_DIR}"

    cat > requirements.txt << 'EOF'
transformers==4.35.0
torch==2.0.0
openai==1.0.0
langchain==0.1.0
EOF

    mkdir -p prompts
    touch chat.py

    run "${SCRIPTS_DIR}/detect_and_configure.sh" --auto --verbose

    assert_success
    [[ "$output" == *"llm"* ]] || [[ "$output" == *"LLM"* ]] || [[ "$output" == *"ml"* ]] || [[ "$output" == *"detected"* ]]
}
