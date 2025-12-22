# Company OS Dashboard E2E Test Suite

This directory contains comprehensive end-to-end tests for the Company OS React dashboard using Playwright.

## Test Coverage

### 1. Login Flow (`login.spec.ts`)
- Redirects to login page when not authenticated
- Successful login with valid credentials
- Validation for empty fields
- Logout functionality

### 2. Dashboard Page (`dashboard.spec.ts`)
- Dashboard title display
- Stats cards (Total Tasks, Completed, Active Agents, Memory Items)
- Recent Tasks section
- Agent Status section
- Connection status indicator
- API data loading
- WebSocket connection handling
- Responsive design across viewports

### 3. Tasks Page (`tasks.spec.ts`)
- Navigation to tasks page
- Task list display
- Search functionality
- Status filter dropdown
- "New Task" button and modal
- Task creation
- Task cards/list items display
- Task action handlers
- State persistence after reload

### 4. Agents Page (`agents.spec.ts`)
- Navigation to agents page
- Agent cards display
- Agent status indicators
- Agent information display
- Activate/deactivate button functionality
- Agent status toggling
- Agent capabilities display
- Multiple agent types
- Agent metrics/stats
- Agent details/expansion
- State persistence
- Mobile responsiveness

### 5. Memory Page (`memory.spec.ts`)
- Navigation to memory page
- Memory items display
- Search functionality
- Memory item cards/list
- Item details display
- Metadata display
- Item action handlers
- Statistics display
- Filter/sort controls
- Empty state handling
- State persistence
- API data loading
- Mobile responsiveness
- Pagination (if present)

### 6. Navigation (`navigation.spec.ts`)
- Sidebar navigation presence
- Navigation to all pages (Dashboard, Tasks, Agents, Memory)
- Active navigation item highlighting
- Sequential page navigation
- Browser back button handling
- Browser forward button handling
- Direct URL navigation
- Authentication persistence across navigation
- Logout functionality
- 404/invalid route handling
- State maintenance after refresh
- Responsive navigation on mobile
- Keyboard navigation

## Prerequisites

1. Backend API must be running on `http://localhost:8000`
2. Frontend dev server must be running on `http://localhost:5173`
3. Playwright browsers must be installed

## Running Tests

### Quick Start
```bash
# From the dashboard directory
./run-e2e-tests.sh
```

### Manual Commands
```bash
# Install Playwright browsers (first time only)
npx playwright install chromium

# Run all tests
npm run test:e2e

# Run tests with UI mode (interactive)
npm run test:e2e:ui

# Run tests in headed mode (see browser)
npm run test:e2e:headed

# View HTML report
npm run test:e2e:report
```

### Run Specific Test Files
```bash
npx playwright test login.spec.ts
npx playwright test dashboard.spec.ts
npx playwright test tasks.spec.ts
npx playwright test agents.spec.ts
npx playwright test memory.spec.ts
npx playwright test navigation.spec.ts
```

### Run Specific Tests
```bash
# Run tests matching a pattern
npx playwright test --grep "should login"

# Run a specific test file with specific test
npx playwright test login.spec.ts --grep "valid credentials"
```

## Test Configuration

Configuration is in `playwright.config.ts`:
- Base URL: `http://localhost:5173`
- Browser: Chromium (Desktop Chrome)
- Parallel execution: Disabled (sequential for stability)
- Retries: 0 in local, 2 in CI
- Screenshots: Only on failure
- Trace: On first retry
- Reporter: HTML report

## Test Strategy

### Authentication
Most tests use a `beforeEach` hook to:
1. Navigate to login page
2. Enter test credentials (`test@example.com` / `password123`)
3. Submit login form
4. Verify redirect to dashboard

### Resilient Selectors
Tests use multiple selector strategies:
- Test IDs (`data-testid`)
- Semantic selectors (role, text content)
- CSS classes (as fallback)
- Flexible text matching with regex

### Graceful Degradation
Tests are designed to handle incomplete implementations:
- Check for element existence before interacting
- Provide console logs for missing features
- Verify either success state or expected behavior
- Handle both populated and empty states

### Timing
Tests include appropriate waits:
- `waitForTimeout` for API calls and animations
- `expect().toBeVisible({ timeout })` for async elements
- Reasonable timeout values (2-10 seconds)

## Test Credentials

Default test account:
- Email: `test@example.com`
- Password: `password123`

## Expected Results

All tests should pass when:
1. Both servers are running correctly
2. Mock API returns expected data
3. Frontend components are fully implemented
4. Navigation routing is configured
5. Authentication flow is working

## Debugging Failed Tests

### View traces
```bash
npx playwright show-trace trace.zip
```

### Run in debug mode
```bash
npx playwright test --debug
```

### Run with headed browser
```bash
npm run test:e2e:headed
```

### Check screenshots
Failed tests create screenshots in `test-results/`

## CI/CD Integration

For CI environments:
```bash
# Install browsers with system dependencies
npx playwright install --with-deps chromium

# Run tests in CI mode (with retries)
CI=true npm run test:e2e
```

## Test Maintenance

When updating the dashboard:
1. Update relevant test files for new features
2. Adjust selectors if component structure changes
3. Add new test files for new pages
4. Update this README with new test coverage

## Known Issues

- WebSocket tests are informational only (non-blocking)
- Some feature tests are conditional based on implementation status
- Mobile menu tests assume standard hamburger menu pattern
- Pagination tests check for existence but don't exhaustively test all functionality

## Contributing

When adding new tests:
1. Follow existing test structure and patterns
2. Use descriptive test names with "should" prefix
3. Include appropriate waits and timeouts
4. Handle both success and failure scenarios
5. Make tests resilient to minor UI changes
6. Add console logs for conditional features
7. Update this README with new coverage
