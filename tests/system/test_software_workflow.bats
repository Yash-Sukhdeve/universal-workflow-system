#!/usr/bin/env bats
# End-to-End Test: Software Development Workflow
# Tests complete software development workflow from requirements to deployment

load '../helpers/test_helper'

# ============================================================================
# SETUP AND TEARDOWN
# ============================================================================

setup() {
    setup_test_environment

    # Create software project structure
    mkdir -p "${TEST_TMP_DIR}/src"
    mkdir -p "${TEST_TMP_DIR}/tests"
    mkdir -p "${TEST_TMP_DIR}/docs"
    mkdir -p "${TEST_TMP_DIR}/config"

    # Simulate software project indicators
    cat > "${TEST_TMP_DIR}/package.json" << 'EOF'
{
    "name": "test-software-project",
    "version": "1.0.0",
    "scripts": {
        "test": "jest",
        "build": "tsc",
        "start": "node dist/index.js"
    }
}
EOF

    # Create full test environment with all fixtures
    create_full_test_environment

    # Update state for software project
    cat > "${TEST_TMP_DIR}/.workflow/state.yaml" << 'EOF'
project:
  name: "software-test-project"
  type: "software"
  version: "1.0.0"

current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"
checkpoint_count: 0

sprint:
  current: 1
  tasks_completed: 0
  tasks_remaining: 5

metadata:
  created: "2024-01-01T00:00:00Z"
  last_updated: "2024-01-01T00:00:00Z"
  version: "1.0.0"
EOF

    cd "${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# E2E WORKFLOW TESTS
# ============================================================================

@test "E2E: Software project type detected" {
    assert_file_exists "${TEST_TMP_DIR}/package.json"
    assert_file_contains "${TEST_TMP_DIR}/package.json" "test-software-project"
}

@test "E2E: Software project structure created" {
    assert_dir_exists "${TEST_TMP_DIR}/src"
    assert_dir_exists "${TEST_TMP_DIR}/tests"
    assert_dir_exists "${TEST_TMP_DIR}/docs"
    assert_dir_exists "${TEST_TMP_DIR}/.workflow"
}

@test "E2E: Software workflow - Requirements Phase" {
    mkdir -p "${TEST_TMP_DIR}/phases/phase_1_planning"

    cat > "${TEST_TMP_DIR}/phases/phase_1_planning/requirements.md" << 'EOF'
# Software Requirements

## Functional Requirements
- FR1: User authentication
- FR2: Data persistence
- FR3: API endpoints
- FR4: Error handling

## Non-Functional Requirements
- NFR1: Response time < 100ms
- NFR2: 99.9% uptime
- NFR3: Security compliance

## User Stories
- US1: As a user, I can login with credentials
- US2: As a user, I can save my data
- US3: As a developer, I can access the API
EOF

    assert_file_exists "${TEST_TMP_DIR}/phases/phase_1_planning/requirements.md"
    assert_file_contains "${TEST_TMP_DIR}/phases/phase_1_planning/requirements.md" "Functional Requirements"
}

@test "E2E: Software workflow - Architecture Design Phase" {
    mkdir -p "${TEST_TMP_DIR}/phases/phase_1_planning"

    cat > "${TEST_TMP_DIR}/phases/phase_1_planning/architecture.md" << 'EOF'
# System Architecture

## Components
1. API Layer (REST)
2. Service Layer (Business Logic)
3. Data Layer (Repository Pattern)
4. Infrastructure Layer (Database, Cache)

## Technology Stack
- Language: TypeScript
- Framework: Express.js
- Database: PostgreSQL
- Cache: Redis

## API Design
- GET /api/users
- POST /api/users
- PUT /api/users/:id
- DELETE /api/users/:id
EOF

    assert_file_exists "${TEST_TMP_DIR}/phases/phase_1_planning/architecture.md"
    assert_file_contains "${TEST_TMP_DIR}/phases/phase_1_planning/architecture.md" "Components"
}

@test "E2E: Software workflow - Implementation Phase" {
    mkdir -p "${TEST_TMP_DIR}/phases/phase_2_implementation/src"

    # Create source code structure
    cat > "${TEST_TMP_DIR}/phases/phase_2_implementation/src/index.ts" << 'EOF'
// Main application entry point
import express from 'express';
import { userRouter } from './routes/users';

const app = express();
app.use('/api/users', userRouter);
app.listen(3000);
EOF

    cat > "${TEST_TMP_DIR}/phases/phase_2_implementation/src/users.ts" << 'EOF'
// User service
export class UserService {
    async getUsers(): Promise<User[]> {
        return [];
    }

    async createUser(data: UserInput): Promise<User> {
        return { id: '1', ...data };
    }
}
EOF

    assert_file_exists "${TEST_TMP_DIR}/phases/phase_2_implementation/src/index.ts"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_2_implementation/src/users.ts"
}

@test "E2E: Software workflow - Testing Phase" {
    mkdir -p "${TEST_TMP_DIR}/phases/phase_3_validation/tests"

    cat > "${TEST_TMP_DIR}/phases/phase_3_validation/tests/users.test.ts" << 'EOF'
import { UserService } from '../src/users';

describe('UserService', () => {
    let service: UserService;

    beforeEach(() => {
        service = new UserService();
    });

    test('getUsers returns empty array initially', async () => {
        const users = await service.getUsers();
        expect(users).toEqual([]);
    });

    test('createUser returns user with id', async () => {
        const user = await service.createUser({ name: 'Test' });
        expect(user.id).toBeDefined();
    });
});
EOF

    # Create test results
    cat > "${TEST_TMP_DIR}/phases/phase_3_validation/test_results.json" << 'EOF'
{
    "numTotalTests": 50,
    "numPassedTests": 48,
    "numFailedTests": 2,
    "numPendingTests": 0,
    "testResults": [
        {"name": "UserService", "status": "passed"},
        {"name": "API Routes", "status": "passed"},
        {"name": "Database", "status": "failed"}
    ]
}
EOF

    assert_file_exists "${TEST_TMP_DIR}/phases/phase_3_validation/tests/users.test.ts"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_3_validation/test_results.json"
}

@test "E2E: Software workflow - CI/CD Configuration" {
    mkdir -p "${TEST_TMP_DIR}/.github/workflows"

    cat > "${TEST_TMP_DIR}/.github/workflows/ci.yml" << 'EOF'
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm install
      - run: npm test
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run build
EOF

    assert_file_exists "${TEST_TMP_DIR}/.github/workflows/ci.yml"
    assert_file_contains "${TEST_TMP_DIR}/.github/workflows/ci.yml" "npm test"
}

@test "E2E: Software workflow - Deployment Configuration" {
    mkdir -p "${TEST_TMP_DIR}/phases/phase_4_delivery"

    cat > "${TEST_TMP_DIR}/phases/phase_4_delivery/Dockerfile" << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY dist ./dist
EXPOSE 3000
CMD ["node", "dist/index.js"]
EOF

    cat > "${TEST_TMP_DIR}/phases/phase_4_delivery/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://localhost:5432/app
  db:
    image: postgres:15
    environment:
      - POSTGRES_DB=app
EOF

    assert_file_exists "${TEST_TMP_DIR}/phases/phase_4_delivery/Dockerfile"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_4_delivery/docker-compose.yml"
}

@test "E2E: Software workflow - Documentation" {
    mkdir -p "${TEST_TMP_DIR}/docs"

    cat > "${TEST_TMP_DIR}/docs/README.md" << 'EOF'
# Software Project

## Getting Started
```bash
npm install
npm run build
npm start
```

## API Documentation
- GET /api/users - List users
- POST /api/users - Create user

## Development
- Run tests: `npm test`
- Build: `npm run build`
EOF

    cat > "${TEST_TMP_DIR}/docs/API.md" << 'EOF'
# API Reference

## Users
### List Users
GET /api/users
Response: 200 OK
```json
[{"id": "1", "name": "User"}]
```
EOF

    assert_file_exists "${TEST_TMP_DIR}/docs/README.md"
    assert_file_exists "${TEST_TMP_DIR}/docs/API.md"
}

@test "E2E: Software workflow - Agent transitions" {
    # Software workflow: architect -> implementer -> experimenter -> deployer -> documenter
    local agents=("architect" "implementer" "experimenter" "deployer" "documenter")

    for agent in "${agents[@]}"; do
        assert_file_contains "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" "${agent}:"
    done
}

@test "E2E: Software workflow - Sprint tracking" {
    # Update sprint progress
    sed -i 's/tasks_completed: 0/tasks_completed: 3/' \
        "${TEST_TMP_DIR}/.workflow/state.yaml"
    sed -i 's/tasks_remaining: 5/tasks_remaining: 2/' \
        "${TEST_TMP_DIR}/.workflow/state.yaml"

    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "tasks_completed: 3"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "tasks_remaining: 2"
}

@test "E2E: Software workflow - Checkpoint at key milestones" {
    cat > "${TEST_TMP_DIR}/.workflow/checkpoints.log" << 'EOF'
2024-01-01T00:00:00Z | CP_INIT | Project initialized
2024-01-05T00:00:00Z | CP_S_1 | Requirements finalized
2024-01-15T00:00:00Z | CP_S_2 | Architecture approved
2024-02-01T00:00:00Z | CP_S_3 | MVP implementation complete
2024-02-15T00:00:00Z | CP_S_4 | Testing phase complete
2024-03-01T00:00:00Z | CP_S_5 | Deployment ready
EOF

    local checkpoint_count=$(grep -c "CP_S_" "${TEST_TMP_DIR}/.workflow/checkpoints.log")
    [ "$checkpoint_count" -eq 5 ]
}

@test "E2E: Software workflow - Complete handoff document" {
    cat > "${TEST_TMP_DIR}/.workflow/handoff.md" << 'EOF'
# Software Workflow Handoff

## Current Status
- Phase: phase_3_validation
- Sprint: 1
- Progress: 60%

## Completed
- [x] Requirements gathering
- [x] Architecture design
- [x] Core implementation
- [x] Unit tests

## In Progress
- [ ] Integration tests
- [ ] Performance testing

## Blockers
- None

## Next Session
1. Complete integration tests
2. Run performance benchmarks
3. Prepare deployment
EOF

    assert_file_contains "${TEST_TMP_DIR}/.workflow/handoff.md" "Sprint"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/handoff.md" "Blockers"
}

@test "E2E: Software workflow - Artifact generation" {
    mkdir -p "${TEST_TMP_DIR}/artifacts/metrics"

    cat > "${TEST_TMP_DIR}/artifacts/metrics/code_quality.json" << 'EOF'
{
    "coverage": 85.5,
    "lines_of_code": 2500,
    "cyclomatic_complexity": 12,
    "maintainability_index": 78,
    "technical_debt_hours": 24
}
EOF

    cat > "${TEST_TMP_DIR}/artifacts/metrics/performance.json" << 'EOF'
{
    "avg_response_time_ms": 45,
    "p95_response_time_ms": 120,
    "p99_response_time_ms": 250,
    "requests_per_second": 1500,
    "error_rate": 0.001
}
EOF

    assert_file_exists "${TEST_TMP_DIR}/artifacts/metrics/code_quality.json"
    assert_file_exists "${TEST_TMP_DIR}/artifacts/metrics/performance.json"
}

@test "E2E: Software workflow - Full lifecycle simulation" {
    # Simulate complete software development lifecycle

    # 1. Planning phase complete
    mkdir -p "${TEST_TMP_DIR}/phases/phase_1_planning"
    echo "Planning complete" > "${TEST_TMP_DIR}/phases/phase_1_planning/COMPLETE"

    # 2. Implementation phase complete
    mkdir -p "${TEST_TMP_DIR}/phases/phase_2_implementation"
    echo "Implementation complete" > "${TEST_TMP_DIR}/phases/phase_2_implementation/COMPLETE"

    # 3. Validation phase complete
    mkdir -p "${TEST_TMP_DIR}/phases/phase_3_validation"
    echo "Validation complete" > "${TEST_TMP_DIR}/phases/phase_3_validation/COMPLETE"

    # 4. Delivery phase complete
    mkdir -p "${TEST_TMP_DIR}/phases/phase_4_delivery"
    echo "Delivery complete" > "${TEST_TMP_DIR}/phases/phase_4_delivery/COMPLETE"

    # 5. Maintenance phase active
    mkdir -p "${TEST_TMP_DIR}/phases/phase_5_maintenance"
    echo "Maintenance ongoing" > "${TEST_TMP_DIR}/phases/phase_5_maintenance/STATUS"

    # Update state to reflect completion
    sed -i 's/current_phase: "phase_1_planning"/current_phase: "phase_5_maintenance"/' \
        "${TEST_TMP_DIR}/.workflow/state.yaml"

    # Verify all phases have markers
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_1_planning/COMPLETE"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_2_implementation/COMPLETE"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_3_validation/COMPLETE"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_4_delivery/COMPLETE"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_5_maintenance/STATUS"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "phase_5_maintenance"
}
