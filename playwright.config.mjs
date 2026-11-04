import { defineConfig } from '@playwright/test';
import site from './website-test.config.mjs';

const port = Number(process.env.SITE_TEST_PORT || 4173);
export default defineConfig({
  testDir: './website-tests',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  workers: 2,
  timeout: 30_000,
  globalTimeout: 15 * 60_000,
  expect: { timeout: 5_000 },
  reporter: [['list'], ['html', { open: 'never' }], ['json', { outputFile: 'test-results/report.json' }]],
  use: {
    baseURL: `http://127.0.0.1:${port}${site.prefix}`,
    reducedMotion: 'reduce',
    actionTimeout: 10_000,
    navigationTimeout: 20_000,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure'
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'webkit', use: { browserName: 'webkit' } }
  ],
  webServer: {
    command: `${site.build ? site.build + ' && ' : ''}node ${site.scriptsDirectory || 'scripts'}/serve-website-tests.mjs`,
    url: `http://127.0.0.1:${port}${site.prefix}`,
    reuseExistingServer: false,
    timeout: 30_000
  }
});
