/**
 * Blacklist Page E2E Tests
 *
 * Tests the /blacklist page functionality and information display.
 *
 * @module e2e/blacklist.spec
 */

import { test, expect } from '@playwright/test';

test.describe('Blacklist Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/blacklist');
    await page.waitForLoadState('networkidle');
  });

  test('renders blacklist page with title', async ({ page }) => {
    // Check page heading
    const heading = page.locator('h1, h2').first();
    await expect(heading).toBeVisible({ timeout: 15000 });
  });

  test('shows blacklist information', async ({ page }) => {
    // Look for informational content about blacklist
    const content = page.locator('text=/Blacklist|address|compliance/i').first();
    await expect(content).toBeVisible({ timeout: 10000 });
  });

  test('has quick links section', async ({ page }) => {
    // Look for links to related pages
    const mintLink = page.locator('a[href*="mint"]').first();
    await expect(mintLink).toBeVisible({ timeout: 10000 });
  });
});
