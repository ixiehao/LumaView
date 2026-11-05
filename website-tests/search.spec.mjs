import { test, expect, site, languages } from './support.mjs';

for (const language of languages) {
  test.describe(`${language} search reading files`, () => {
    test.use({ javaScriptEnabled: false, viewport: { width: 320, height: 568 }, isMobile: true, hasTouch: true });
    test('raw HTML, Markdown and AI index are available without JavaScript', async ({ page, baseURL }) => {
      const route = language === 'en' ? './' : `${language}/`;
      const canonical = site.url + (language === 'en' ? '' : language + '/');
      const response = await page.goto(route);
      expect(response.status()).toBe(200);
      await expect(page.locator('html')).toHaveAttribute('lang', language === 'zh' ? 'zh-CN' : language);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', canonical);
      await expect(page.locator('link[type="text/markdown"]')).toHaveAttribute('href', canonical + 'index.md');
      await expect(page.locator('link[rel="describedby"]')).toHaveAttribute('href', site.url + 'llms.txt');
      expect(await page.locator('main').innerText()).not.toMatch(/\{\{\w+\}\}/);
      expect((await page.locator('main').innerText()).trim().length).toBeGreaterThan(80);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      const markdown = await page.request.get(new URL('index.md', page.url()).href);
      expect(markdown.status()).toBe(200);
      expect(markdown.headers()['content-type']).toContain('text/markdown');
      expect(await markdown.text()).toContain(`<${canonical}>`);
      const index = await page.request.get(new URL('llms.txt', baseURL).href);
      expect(index.status()).toBe(200);
      const text = await index.text();
      for (const id of site.languages) expect(text).toContain(site.url + (id === 'en' ? '' : id + '/') + 'index.md');
    });
  });
}
