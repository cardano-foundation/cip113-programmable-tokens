/**
 * Navigation E2E Tests
 *
 * Tests basic navigation and page rendering for all main pages.
 *
 * @module e2e/navigation.spec
 */

import { test, expect } from '@playwright/test';

test.describe('Navigation', () => {
  test('homepage renders correctly', async ({ page }) => {
    await page.goto('/');

    // Wait for the page to fully load (MeshProvider loads dynamically)
    await page.waitForLoadState('networkidle');

    // Check page title
    await expect(page).toHaveTitle(/CIP-113|Programmable Tokens/i);

    // Check main heading exists - wait longer for dynamic content
    const heading = page.locator('h1').first();
    await expect(heading).toBeVisible({ timeout: 15000 });
  });

  test('navigation header is visible', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Check header/nav exists
    const nav = page.locator('nav, header').first();
    await expect(nav).toBeVisible({ timeout: 10000 });
  });

  test('can navigate to mint page', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Click on Mint link
    await page.click('a[href="/mint"]', { timeout: 10000 });

    // Verify URL changed
    await expect(page).toHaveURL('/mint');
  });

  test('can navigate to transfer page', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Click on Transfer link
    await page.click('a[href="/transfer"]', { timeout: 10000 });

    // Verify URL changed
    await expect(page).toHaveURL('/transfer');
  });

  test('can navigate to deploy page', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Click on Deploy link
    await page.click('a[href="/deploy"]', { timeout: 10000 });

    // Verify URL changed
    await expect(page).toHaveURL('/deploy');
  });

  test('can navigate to blacklist page', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Click on Blacklist link
    await page.click('a[href="/blacklist"]', { timeout: 10000 });

    // Verify URL changed
    await expect(page).toHaveURL('/blacklist');
  });

  test('can navigate to dashboard page', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Click on Dashboard link
    await page.click('a[href="/dashboard"]', { timeout: 10000 });

    // Verify URL changed
    await expect(page).toHaveURL('/dashboard');
  });
});
