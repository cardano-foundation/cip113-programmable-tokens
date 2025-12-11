/**
 * Deploy Page E2E Tests
 *
 * Tests the /deploy page functionality including protocol status display.
 *
 * @module e2e/deploy.spec
 */

import { test, expect } from '@playwright/test';

test.describe('Deploy Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/deploy');
    await page.waitForLoadState('networkidle');
  });

  test('renders deploy page with title', async ({ page }) => {
    // Check page heading
    const heading = page.locator('h1, h2').first();
    await expect(heading).toBeVisible({ timeout: 15000 });
  });

  test('shows protocol status card', async ({ page }) => {
    // Look for protocol status section
    const statusSection = page.locator('text=/Protocol|Status|Deploy/i').first();
    await expect(statusSection).toBeVisible({ timeout: 10000 });
  });

  test('displays quick action buttons', async ({ page }) => {
    // Check for action buttons/links
    const mintLink = page.locator('a[href="/mint"]').first();
    await expect(mintLink).toBeVisible({ timeout: 10000 });
  });
});
