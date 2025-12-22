# Company OS Unit Tests

Comprehensive unit tests for Company OS core modules using pytest and pytest-asyncio.

## Quick Start

```bash
# Run all Company OS unit tests
pytest tests/unit/company_os/ -v

# Run specific module tests
pytest tests/unit/company_os/test_event_store.py -v
pytest tests/unit/company_os/test_auth_service.py -v
pytest tests/unit/company_os/test_memory_service.py -v

# Run with coverage report
pytest tests/unit/company_os/ --cov=company_os.core --cov-report=html
open htmlcov/index.html
```

## Test Files

| File | Tests | Lines | Coverage |
|------|-------|-------|----------|
| `test_event_store.py` | 29 | 674 | EventStore, Event, EventPublisher |
| `test_auth_service.py` | 29 | 728 | AuthService, passwords, JWT, RBAC |
| `test_memory_service.py` | 34 | 810 | SemanticMemory, embeddings, search |
| **TOTAL** | **92** | **2,212** | - |

## Test Coverage by Module

### 1. test_event_store.py
Tests event sourcing with optimistic concurrency control.

**Key Features:**
- Event creation and parsing
- Stream versioning
- Optimistic locking
- Multi-event appending
- Stream reading with pagination
- Event type filtering
- Pub/sub pattern

**Example:**
```python
pytest tests/unit/company_os/test_event_store.py::TestEventStore::test_append_version_conflict -v
```

### 2. test_auth_service.py
Tests authentication, authorization, and token management.

**Key Features:**
- Bcrypt password hashing
- User creation with organization
- JWT access token creation
- Refresh token rotation
- Token expiration
- Role-based permissions (RBAC)
- Permission checking

**Example:**
```python
pytest tests/unit/company_os/test_auth_service.py::TestTokenManagement::test_refresh_tokens_success -v
```

### 3. test_memory_service.py
Tests semantic memory with vector embeddings.

**Key Features:**
- Embedding generation (OpenAI, Sentence Transformers)
- Semantic similarity search
- Metadata filtering
- Memory consolidation
- Age-based pruning
- SQL injection prevention
- Agent context building

**Example:**
```python
pytest tests/unit/company_os/test_memory_service.py::TestSemanticMemoryService::test_search_memories -v
```

## Test Infrastructure

### Mocking Strategy

All tests use comprehensive mocking:
- **asyncpg Pool/Connection**: Fully mocked with AsyncContextManagerMock
- **OpenAI API**: Mocked embedding responses
- **Database transactions**: Mock context managers
- **External services**: All mocked for isolation

### Fixtures

Common fixtures from `conftest.py`:
```python
mock_pool          # Mock asyncpg.Pool
mock_settings      # Mock Settings
sample_user_id     # UUID for tests
sample_org_id      # UUID for tests
```

## Running Tests

### By Category
```bash
# All async tests
pytest tests/unit/company_os/ -v -k "asyncio"

# All event store tests
pytest tests/unit/company_os/ -v -k "event"

# All auth tests
pytest tests/unit/company_os/ -v -k "auth"

# All memory tests
pytest tests/unit/company_os/ -v -k "memory"
```

### By Test Class
```bash
# Event store tests
pytest tests/unit/company_os/test_event_store.py::TestEventStore -v

# Password hashing tests
pytest tests/unit/company_os/test_auth_service.py::TestPasswordHashing -v

# Memory search tests
pytest tests/unit/company_os/test_memory_service.py::TestSemanticMemoryService -v
```

### With Output
```bash
# Show print statements
pytest tests/unit/company_os/ -v -s

# Show local variables on failure
pytest tests/unit/company_os/ -v -l

# Stop on first failure
pytest tests/unit/company_os/ -v -x
```

### Coverage Reports
```bash
# Terminal coverage report
pytest tests/unit/company_os/ --cov=company_os.core --cov-report=term-missing

# HTML coverage report
pytest tests/unit/company_os/ --cov=company_os.core --cov-report=html
open htmlcov/index.html

# XML coverage report (for CI)
pytest tests/unit/company_os/ --cov=company_os.core --cov-report=xml
```

## Test Markers

```python
@pytest.mark.asyncio     # Async test (requires pytest-asyncio)
@pytest.mark.unit        # Unit test
@pytest.mark.parametrize # Parametrized test
```

## Dependencies

Install test dependencies:
```bash
pip install pytest pytest-asyncio pytest-cov
```

Application dependencies (mocked in tests):
```bash
pip install asyncpg passlib[bcrypt] PyJWT numpy openai
```

## Test Structure

Each test file follows this pattern:

```python
"""
Unit Tests for <Module>.

Brief description of what is tested.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock

class AsyncContextManagerMock:
    """Helper for mocking async context managers."""
    # ... implementation ...

class Test<Feature>:
    """Tests for <Feature> functionality."""

    @pytest.fixture
    def mock_dependency(self):
        """Create mock dependency."""
        return MagicMock()

    @pytest.mark.asyncio
    async def test_<scenario>(self, mock_dependency):
        """Test <specific scenario>."""
        # Setup
        # Execute
        # Assert
```

## Common Patterns

### Mocking AsyncPG Connection
```python
mock_conn = AsyncMock()
mock_conn.fetchval = AsyncMock(return_value=expected_value)
mock_conn.fetchrow = AsyncMock(return_value=expected_row)
mock_conn.fetch = AsyncMock(return_value=expected_rows)
mock_conn.execute = AsyncMock()

mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))
```

### Testing Async Functions
```python
@pytest.mark.asyncio
async def test_async_function(self, service):
    """Test async function."""
    result = await service.some_async_method()
    assert result is not None
```

### Testing Exceptions
```python
with pytest.raises(ExpectedException) as exc_info:
    await service.failing_method()

assert "expected message" in str(exc_info.value)
```

## Debugging Tests

### Run specific test with full output
```bash
pytest tests/unit/company_os/test_auth_service.py::TestAuthentication::test_authenticate_success -vvs
```

### Use pytest debugger
```bash
pytest tests/unit/company_os/test_event_store.py::TestEventStore::test_append_version_conflict --pdb
```

### Show warnings
```bash
pytest tests/unit/company_os/ -v -W default
```

## CI/CD Integration

### GitHub Actions Example
```yaml
- name: Run Unit Tests
  run: |
    pytest tests/unit/company_os/ \
      --cov=company_os.core \
      --cov-report=xml \
      --junitxml=junit.xml \
      -v

- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    file: ./coverage.xml
```

### GitLab CI Example
```yaml
test:
  script:
    - pytest tests/unit/company_os/ --cov=company_os.core --cov-report=term --junitxml=report.xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      junit: report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
```

## Best Practices

1. **Test Isolation**: Each test is independent, uses mocks, no shared state
2. **Descriptive Names**: Test names describe what they test
3. **AAA Pattern**: Arrange, Act, Assert structure
4. **Mock External Dependencies**: Database, APIs, file system all mocked
5. **Test Edge Cases**: Invalid inputs, empty results, error conditions
6. **Test Security**: SQL injection, token validation, permission checks

## Troubleshooting

### Issue: "RuntimeError: Event loop is closed"
**Solution**: Use `pytest-asyncio` fixture scope:
```python
@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()
```

### Issue: "AsyncMock object not awaitable"
**Solution**: Use `AsyncMock()` for async methods, `MagicMock()` for sync:
```python
mock_conn.fetchval = AsyncMock(return_value=value)  # Async
mock_pool.acquire = MagicMock(return_value=ctx)     # Sync (returns ctx manager)
```

### Issue: "Transaction context manager not working"
**Solution**: Mock both acquire and transaction:
```python
mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))
```

## See Also

- [TEST_COVERAGE_REPORT.md](TEST_COVERAGE_REPORT.md) - Detailed coverage analysis
- [../../conftest.py](../../conftest.py) - Shared fixtures
- [Company OS Documentation](../../../company_os/README.md) - Module documentation

## Contributing

When adding new tests:

1. Follow existing test structure and naming
2. Use descriptive test names: `test_<feature>_<scenario>`
3. Mock all external dependencies
4. Test edge cases and error conditions
5. Update this README and TEST_COVERAGE_REPORT.md
6. Ensure tests pass: `pytest tests/unit/company_os/ -v`

---

Last Updated: 2025-12-17
Test Count: 92 tests
Test Framework: pytest + pytest-asyncio
