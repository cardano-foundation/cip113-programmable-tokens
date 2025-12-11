/**
 * Mint Page E2E Tests
 *
 * Tests the /mint page form rendering and validation.
 * Note: Actual minting requires a wallet connection.
 *
 * @module e2e/mint.spec
 */

import { test, expect } from '@playwright/test';

test.describe('Mint Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/mint');
    await page.waitForLoadState('networkidle');
  });

  test('renders mint page with heading', async ({ page }) => {
    // Check page heading
    const heading = page.locator('h1, h2').first();
    await expect(heading).toBeVisible({ timeout: 15000 });
  });

  test('shows form elements', async ({ page }) => {
    // Look for any input field
    const input = page.locator('input').first();
    await expect(input).toBeVisible({ timeout: 10000 });
  });

  test('shows wallet connection prompt when not connected', async ({ page }) => {
    // Look for connect wallet button or message
    const connectElement = page.locator('text=/connect|wallet/i').first();
    await expect(connectElement).toBeVisible({ timeout: 10000 });
  });
});
