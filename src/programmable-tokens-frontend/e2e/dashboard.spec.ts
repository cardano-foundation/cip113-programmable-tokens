/**
 * Dashboard Page E2E Tests
 *
 * Tests the /dashboard page rendering and content display.
 *
 * @module e2e/dashboard.spec
 */

import { test, expect } from '@playwright/test';

test.describe('Dashboard Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
  });

  test('renders dashboard page', async ({ page }) => {
    // Check page heading
    const heading = page.locator('h1, h2').first();
    await expect(heading).toBeVisible({ timeout: 15000 });
  });

  test('shows dashboard content', async ({ page }) => {
    // Look for dashboard-related content
    const content = page.locator('text=/Dashboard|Overview|Token|Balance/i').first();
    await expect(content).toBeVisible({ timeout: 10000 });
  });

  test('has navigation to other pages', async ({ page }) => {
    // Check for links to mint/transfer
    const mintLink = page.locator('a[href="/mint"]');
    await expect(mintLink.first()).toBeVisible({ timeout: 10000 });
  });
});
