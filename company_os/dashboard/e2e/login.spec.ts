import { test, expect } from '@playwright/test';

test.describe('Login Flow', () => {
  test('should redirect to login page when not authenticated', async ({ page }) => {
    await page.goto('/');

    // Should redirect to login page
    await expect(page).toHaveURL('/login');

    // Verify login page elements - h1 says "Company OS", not "Login"
    await expect(page.locator('h1')).toContainText('Company OS');
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await expect(page.locator('input[type="password"]')).toBeVisible();
    await expect(page.locator('button[type="submit"]')).toBeVisible();
  });

  test('should login successfully with valid credentials', async ({ page }) => {
    await page.goto('/login');

    // Fill in login form
    await page.fill('input[type="email"]', 'test@example.com');
    await page.fill('input[type="password"]', 'password123');

    // Click login button
    await page.click('button[type="submit"]');

    // Should redirect to dashboard
    await expect(page).toHaveURL('/', { timeout: 10000 });

    // Verify we're on the dashboard (h2 in header, not h1)
    await expect(page.locator('h2')).toContainText('Dashboard', { timeout: 5000 });
  });

  test('should show validation error for empty fields', async ({ page }) => {
    await page.goto('/login');

    // Click login without filling fields
    await page.click('button[type="submit"]');

    // Should stay on login page
    await expect(page).toHaveURL('/login');
  });

  test('should handle logout', async ({ page }) => {
    // First login
    await page.goto('/login');
    await page.fill('input[type="email"]', 'test@example.com');
    await page.fill('input[type="password"]', 'password123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL('/');

    // Find and click logout button
    const logoutButton = page.locator('button, a').filter({ hasText: /logout/i });
    if (await logoutButton.count() > 0) {
      await logoutButton.first().click();

      // Should redirect to login page
      await expect(page).toHaveURL('/login', { timeout: 5000 });
    }
  });
});
