# Company OS API Integration Tests

Comprehensive integration tests for Company OS FastAPI endpoints using pytest, pytest-asyncio, and httpx.

## Test Coverage

### 1. Authentication API (`test_auth_api.py`)
- **POST /api/auth/register**
  - Success with all fields
  - Success without optional org_name
  - Duplicate email handling
  - Invalid email format validation
  - Missing required fields
  - Empty password handling

- **POST /api/auth/login**
  - Success with correct credentials
  - Wrong password
  - Inactive user account
  - Non-existent user
  - Missing password validation

- **POST /api/auth/refresh**
  - Success token refresh
  - Invalid token
  - Expired token
  - Revoked token

- **POST /api/auth/logout**
  - Success logout
  - Already revoked token

- **GET /api/auth/me**
  - Authenticated user
  - Unauthenticated request
  - Invalid token
  - Expired token
  - Deleted user (token valid but user gone)

- **GitHub OAuth**
  - Not implemented (501 status)

### 2. Tasks API (`test_tasks_api.py`)
- **POST /api/tasks** (Create)
  - Success with all fields
  - Success with due date
  - Invalid priority validation
  - Unauthorized access

- **GET /api/tasks** (List)
  - Success listing all tasks
  - Filter by status
  - Filter by priority
  - Filter by assigned agent
  - Pagination (limit & offset)
  - Unauthorized access

- **GET /api/tasks/{id}** (Get)
  - Task found
  - Task not found (404)
  - Invalid UUID format

- **PUT /api/tasks/{id}** (Update)
  - Success update
  - Task not found

- **POST /api/tasks/{id}/assign** (Assign)
  - Assign to agent (activates agent via UWS)
  - Assign to user
  - Missing assignee validation

- **POST /api/tasks/{id}/complete** (Complete)
  - Success completion

- **DELETE /api/tasks/{id}** (Delete)
  - Success deletion
  - Task not found

- **Event Sourcing**
  - TaskCreated event generation
  - TaskUpdated event generation
  - Events applied to projections

### 3. Memory API (`test_memory_api.py`)
- **POST /api/memory/store**
  - Success with all memory types (task, decision, code_pattern, handoff, skill, error)
  - Invalid memory type
  - Missing content validation
  - Unauthorized access

- **POST /api/memory/search**
  - Success search
  - Multiple memory types
  - With metadata filters
  - Invalid memory type
  - Missing query validation

- **POST /api/memory/context**
  - Success context building
  - Missing required fields

- **GET /api/memory/similar-tasks**
  - Success finding similar tasks
  - With agent and outcome filters

- **GET /api/memory/decisions**
  - Success finding past decisions

- **GET /api/memory/code-patterns**
  - Success finding code patterns
  - Language filter

- **GET /api/memory/errors**
  - Success finding similar errors

- **PUT /api/memory/{id}/quality**
  - Success quality update
  - Invalid score (out of range)
  - Invalid UUID

- **POST /api/memory/consolidate**
  - Success consolidation
  - Invalid memory type

- **POST /api/memory/prune**
  - Success pruning old memories
  - Invalid memory type

## Running Tests

### Install Dependencies
```bash
pip install pytest pytest-asyncio httpx
```

### Run All Tests
```bash
# From project root
pytest tests/integration/company_os/

# With verbose output
pytest tests/integration/company_os/ -v

# Run specific test file
pytest tests/integration/company_os/test_auth_api.py

# Run specific test class
pytest tests/integration/company_os/test_auth_api.py::TestRegisterEndpoint

# Run specific test
pytest tests/integration/company_os/test_auth_api.py::TestRegisterEndpoint::test_register_success
```

### Run with Coverage
```bash
pytest tests/integration/company_os/ --cov=company_os --cov-report=html
```

### Run Only Integration Tests
```bash
pytest tests/integration/company_os/ -m integration
```

## Test Architecture

### Fixtures
- `fastapi_app`: FastAPI application instance
- `mock_pool`: Mocked asyncpg database pool
- `mock_app_state`: Mocked application state with all services
- `mock_token_payload`: Sample JWT token payload for authentication
- `sample_user`, `sample_org`, `sample_tokens`: Sample data objects

### Mocking Strategy
Tests use `unittest.mock` to mock:
- Database connections (asyncpg.Pool)
- Service layer methods (AuthService, MemoryService, EventStore)
- Authentication dependencies (get_current_user)
- External integrations (UWS adapter)

### HTTP Client
Tests use `httpx.AsyncClient` with `ASGITransport` to make actual HTTP requests to the FastAPI app without requiring a running server.

## Key Patterns

### Testing Authenticated Endpoints
```python
with patch("company_os.api.security.get_current_user") as mock_auth:
    mock_auth.return_value = mock_token_payload

    async with AsyncClient(...) as client:
        response = await client.get(
            "/api/endpoint",
            headers={"Authorization": "Bearer test.token"}
        )
```

### Testing Event Sourcing
```python
# Verify event was created
mock_event_store.append.assert_called_once()
call_args = mock_event_store.append.call_args
events = call_args.kwargs["events"]
assert events[0].event_type == "TaskCreated"

# Verify event was applied to projections
mock_projection_manager.apply_event.assert_called_once()
```

### Testing Validation
```python
# Pydantic validation errors return 422
response = await client.post("/api/endpoint", json={"invalid": "data"})
assert response.status_code == 422
```

## Notes

- Tests use mocked dependencies for isolation
- No actual database required (all DB operations mocked)
- No actual authentication tokens generated (mocked)
- Tests verify API contract, request/response schemas, and error handling
- Event sourcing behavior verified through mock assertions

## Future Enhancements

1. Add database integration tests with test database
2. Add end-to-end tests with real auth flow
3. Add performance tests for high-load scenarios
4. Add contract tests for API versioning
5. Add security tests (SQL injection, XSS, etc.)
