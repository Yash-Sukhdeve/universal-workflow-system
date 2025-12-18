import { defineConfig, devices } from '@playwright/test';

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',
  timeout: 60000, // 60 second timeout per test
  expect: {
    timeout: 10000, // 10 second timeout for assertions
  },
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    navigationTimeout: 30000, // 30 second navigation timeout
    actionTimeout: 15000, // 15 second action timeout
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Web servers for E2E testing
  webServer: process.env.SKIP_WEBSERVER ? undefined : [
    {
      command: 'cd .. && python3 mock_server.py',
      url: 'http://localhost:8000/health',
      reuseExistingServer: !process.env.CI,
      timeout: 60000,
      stdout: 'pipe',
      stderr: 'pipe',
    },
    {
      command: 'VITE_USE_POLLING=true npm run dev',
      url: 'http://localhost:5173',
      reuseExistingServer: !process.env.CI,
      timeout: 60000,
      stdout: 'pipe',
      stderr: 'pipe',
    },
  ],
});
