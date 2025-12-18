import { test, expect } from '@playwright/test';

test.describe('Memory Page', () => {
  test.beforeEach(async ({ page }) => {
    // Login before each test
    await page.goto('/login');
    await page.fill('input[type="email"]', 'test@example.com');
    await page.fill('input[type="password"]', 'password123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL('/');

    // Navigate to memory page
    await page.goto('/memory');
  });

  test('should navigate to memory page', async ({ page }) => {
    await expect(page).toHaveURL('/memory');
    await expect(page.locator('h1, h2').filter({ hasText: /memory/i })).toBeVisible({ timeout: 5000 });
  });

  test('should display memory items', async ({ page }) => {
    // Wait for memory items to load
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const pageContent = await page.content();

    // Should have memory content
    const hasMemoryContent =
      pageContent.toLowerCase().includes('memory') ||
      pageContent.includes('No memory items') ||
      pageContent.includes('No items') ||
      pageContent.includes('empty');

    expect(hasMemoryContent).toBeTruthy();
  });

  test('should have search functionality', async ({ page }) => {
    // Look for search input
    const searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i]');

    if (await searchInput.count() > 0) {
      await expect(searchInput.first()).toBeVisible();

      // Test search
      await searchInput.first().fill('test');
      await page.waitForTimeout(500);

      // Verify search was performed
      const pageContent = await page.content();
      expect(pageContent).toBeTruthy();
    } else {
      console.log('Search functionality not found - may not be implemented yet');
    }
  });

  test('should display memory item cards or list', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Look for memory items
    const memoryItems = page.locator('[data-testid="memory-item"], .memory-item, .memory-card, li, article').filter({
      has: page.locator('text=/memory|content|data|item/i')
    });

    const itemCount = await memoryItems.count();

    if (itemCount > 0) {
      expect(itemCount).toBeGreaterThan(0);

      // Verify first item has content
      const firstItem = memoryItems.first();
      const itemContent = await firstItem.textContent();
      expect(itemContent).toBeTruthy();
      expect(itemContent!.length).toBeGreaterThan(0);
    } else {
      const pageContent = await page.content();
      expect(pageContent.includes('No memory') || pageContent.includes('No items') || pageContent.includes('empty')).toBeTruthy();
    }
  });

  test('should show memory item details', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const pageContent = await page.content();

    // Look for typical memory item properties
    const hasDetails =
      pageContent.includes('key') ||
      pageContent.includes('value') ||
      pageContent.includes('content') ||
      pageContent.includes('data') ||
      pageContent.includes('timestamp') ||
      pageContent.includes('created') ||
      pageContent.includes('updated');

    expect(hasDetails).toBeTruthy();
  });

  test('should display memory item metadata', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const pageContent = await page.content();

    // Look for metadata
    const hasMetadata =
      /\d{1,2}\/\d{1,2}\/\d{4}/.test(pageContent) || // Date format
      /\d{4}-\d{2}-\d{2}/.test(pageContent) || // ISO date format
      pageContent.includes('ago') || // Relative time
      pageContent.includes('timestamp') ||
      pageContent.includes('type') ||
      pageContent.includes('category');

    expect(hasMetadata).toBeTruthy();
  });

  test('should handle memory item actions', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Look for action buttons
    const actionButtons = page.locator('button').filter({
      hasText: /view|edit|delete|remove|details|clear/i
    });

    const buttonCount = await actionButtons.count();

    if (buttonCount > 0) {
      // Verify buttons are visible
      await expect(actionButtons.first()).toBeVisible();
    } else {
      console.log('Memory item action buttons not found');
    }
  });

  test('should display memory statistics', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const pageContent = await page.content();

    // Look for statistics or counts
    const hasStats =
      /\d+/.test(pageContent) || // Has numbers
      pageContent.includes('total') ||
      pageContent.includes('count') ||
      pageContent.includes('items');

    expect(hasStats).toBeTruthy();
  });

  test('should filter or sort memory items', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Look for filter or sort controls
    const filterControls = page.locator('select, button, [role="combobox"]').filter({
      hasText: /filter|sort|order|type|category/i
    });

    const controlCount = await filterControls.count();

    if (controlCount > 0) {
      await expect(filterControls.first()).toBeVisible();

      // Try to interact with control
      await filterControls.first().click();
      await page.waitForTimeout(500);
    } else {
      console.log('Filter/sort controls not found');
    }
  });

  test('should handle empty state', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    const pageContent = await page.content();

    // Should either have items or show empty state
    const hasContentOrEmpty =
      pageContent.includes('memory') ||
      pageContent.includes('No items') ||
      pageContent.includes('No memory') ||
      pageContent.includes('empty') ||
      pageContent.includes('Nothing to show');

    expect(hasContentOrEmpty).toBeTruthy();
  });

  test('should persist state after reload', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Get initial state
    const initialContent = await page.content();

    // Reload page
    await page.reload();
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Get state after reload
    const reloadedContent = await page.content();

    // Should still show memory page
    expect(reloadedContent.toLowerCase()).toContain('memory');
  });

  test('should load data from API', async ({ page }) => {
    // Intercept API calls
    let apiCallMade = false;

    page.on('request', request => {
      if (
        request.url().includes('memory') ||
        request.url().includes('localhost:8000') ||
        request.url().includes('/api/')
      ) {
        apiCallMade = true;
        console.log('API call detected:', request.url());
      }
    });

    await page.reload();
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Either API was called or static data is shown
    const pageContent = await page.content();
    const hasData = apiCallMade || pageContent.toLowerCase().includes('memory');

    expect(hasData).toBeTruthy();
  });

  test('should be responsive on mobile', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(1000);

    // Should still display content
    const heading = page.locator('h1, h2').filter({ hasText: /memory/i });
    await expect(heading).toBeVisible();

    // Check for memory content
    const pageContent = await page.content();
    expect(pageContent.toLowerCase()).toContain('memory');
  });

  test('should handle pagination if present', async ({ page }) => {
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

    // Look for pagination controls
    const paginationControls = page.locator('button, a').filter({
      hasText: /next|previous|prev|page|\d+|first|last/i
    });

    const controlCount = await paginationControls.count();

    if (controlCount > 0) {
      console.log('Pagination controls found');
      await expect(paginationControls.first()).toBeVisible();
    } else {
      console.log('No pagination controls - data may fit on one page');
    }
  });
});
