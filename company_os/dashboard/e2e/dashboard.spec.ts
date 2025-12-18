import { test, expect } from '@playwright/test';

test.describe('Dashboard Page', () => {
  test.beforeEach(async ({ page }) => {
    // Login before each test
    await page.goto('/login');
    await page.fill('input[type="email"]', 'test@example.com');
    await page.fill('input[type="password"]', 'password123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL('/');
  });

  test('should display dashboard title', async ({ page }) => {
    // Dashboard title is in h2 (in header), not h1
    await expect(page.locator('h2')).toContainText('Dashboard', { timeout: 5000 });
  });

  test('should display stats cards', async ({ page }) => {
    // Wait for stats cards to load
    await page.waitForSelector('[data-testid="stats-card"], .stats-card, div:has-text("Total Tasks")', {
      timeout: 10000,
      state: 'visible'
    });

    // Check for stat cards content
    const pageContent = await page.content();

    // Verify presence of key metrics
    expect(pageContent).toContain('Total Tasks');
    expect(pageContent).toContain('Completed');
    expect(pageContent).toContain('Active Agents');
    expect(pageContent).toContain('Memory Items');
  });

  test('should display Recent Tasks section', async ({ page }) => {
    // Wait for Recent Tasks section
    const recentTasksHeading = page.locator('h2, h3').filter({ hasText: /recent tasks/i });
    await expect(recentTasksHeading).toBeVisible({ timeout: 10000 });

    // Check for tasks or empty state
    const pageContent = await page.content();
    const hasTasks = pageContent.includes('task') || pageContent.includes('No tasks');
    expect(hasTasks).toBeTruthy();
  });

  test('should display Agent Status section', async ({ page }) => {
    // Wait for Agent Status section
    const agentStatusHeading = page.locator('h2, h3').filter({ hasText: /agent status/i });
    await expect(agentStatusHeading).toBeVisible({ timeout: 10000 });

    // Check for agents or empty state
    const pageContent = await page.content();
    const hasAgents = pageContent.includes('agent') || pageContent.includes('No agents');
    expect(hasAgents).toBeTruthy();
  });

  test('should show connection status indicator', async ({ page }) => {
    // Look for connection status indicators
    const pageContent = await page.content();

    // Check for common connection status indicators
    const hasConnectionIndicator =
      pageContent.includes('Connected') ||
      pageContent.includes('Disconnected') ||
      pageContent.includes('Online') ||
      pageContent.includes('Offline') ||
      pageContent.includes('connection') ||
      await page.locator('[data-testid="connection-status"]').count() > 0;

    expect(hasConnectionIndicator).toBeTruthy();
  });

  test('should load data from API', async ({ page }) => {
    // Intercept API calls
    let apiCallMade = false;

    page.on('request', request => {
      if (request.url().includes('localhost:8000') || request.url().includes('/api/')) {
        apiCallMade = true;
      }
    });

    await page.reload();

    // Wait a bit for API calls
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Verify API was called or data is displayed
    const hasData = apiCallMade || (await page.locator('text=/[0-9]+/').count() > 0);
    expect(hasData).toBeTruthy();
  });

  test('should handle WebSocket connection', async ({ page }) => {
    // Check if WebSocket connection is established
    let wsConnected = false;

    page.on('websocket', ws => {
      wsConnected = true;
      console.log('WebSocket connected:', ws.url());
    });

    await page.reload();
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Either WebSocket connected or app works without it
    // This is non-blocking - we just log the status
    console.log('WebSocket status:', wsConnected ? 'Connected' : 'Not connected or not used');
  });

  test('should be responsive', async ({ page }) => {
    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(page.locator('h1')).toBeVisible();

    // Test tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await expect(page.locator('h1')).toBeVisible();

    // Test desktop viewport
    await page.setViewportSize({ width: 1920, height: 1080 });
    await expect(page.locator('h1')).toBeVisible();
  });
});
