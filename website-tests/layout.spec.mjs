import { test, expect, site, languages, viewports, openPage, measureLayout, checkLayout, panelBounds } from './support.mjs';

for (const language of languages) for (const viewport of viewports) {
  test.describe(`${language} ${viewport.width}x${viewport.height}`, () => {
    const mobile = viewport.width <= 430 || viewport.height <= 430;
    test.use({ viewport, isMobile: mobile, hasTouch: mobile, deviceScaleFactor: mobile ? 2 : 1 });
    test('page, cards, controls and complete screenshots fit', async ({ page }, testInfo) => {
      await openPage(page, language);
      await checkLayout(page, testInfo);
      if (site.faq) {
        await page.locator(site.faq).evaluateAll(items => items.forEach(item => { item.open = true; }));
        await checkLayout(page, testInfo);
      }
    });
  });
}

for (const language of languages) for (const viewport of [{ width: 320, height: 568 }, { width: 740, height: 360 }, { width: 1280, height: 900 }]) {
  test.describe(`${language} controls ${viewport.width}x${viewport.height}`, () => {
    const mobile = viewport.width < 800;
    test.use({ viewport, isMobile: mobile, hasTouch: mobile, deviceScaleFactor: mobile ? 2 : 1 });
    test('language menu, installation dialogs and focus', async ({ page }, testInfo) => {
      await openPage(page, language);
      if (site.picker) {
        const picker = page.locator(site.picker);
        await picker.locator('summary').click();
        await expect(picker).toHaveAttribute('open');
        const links = picker.locator('a');
        await expect(links).toHaveCount(site.languages.length);
        for (const link of await links.all()) {
          const href = new URL(await link.getAttribute('href'), page.url());
          expect(href.pathname.startsWith(site.prefix)).toBe(true);
        }
        expect(await picker.locator(site.menu).evaluate(panelBounds)).toMatchObject({ inside: true, textFits: true });
        await page.keyboard.press('Escape');
        await expect(picker).not.toHaveAttribute('open');
        await expect(picker.locator('summary')).toBeFocused();
      }
      if (site.faq) for (const summary of await page.locator(site.faq + ' > summary').all()) await summary.click();
      for (const trigger of await page.locator('[data-install-guide]').all()) {
        await trigger.click();
        const dialog = page.locator('#install-dialog');
        await expect(dialog).toBeVisible();
        expect(await dialog.evaluate(panelBounds)).toMatchObject({ inside: true, textFits: true });
        await checkLayout(page, testInfo, { root: '#install-dialog', cards: null, uniform: [] });
        const scroll = await dialog.evaluate(el => ({ extra: el.scrollHeight - el.clientHeight, overflow: getComputedStyle(el).overflowY }));
        if (scroll.extra > 2) {
          expect(['auto', 'scroll']).toContain(scroll.overflow);
          await dialog.evaluate(el => { el.scrollTop = el.scrollHeight; });
          expect(await dialog.evaluate(el => el.scrollTop)).toBeGreaterThan(0);
        }
        await page.keyboard.press('Escape');
        await expect(dialog).not.toBeVisible();
        await expect(trigger).toBeFocused();
      }
      if (site.picker) {
        await page.evaluate(() => scrollTo(0, 0));
        const picker = page.locator(site.picker);
        await picker.locator('summary').click();
        const other = language === 'en' ? site.languages.find(id => id !== 'en') : 'en';
        if (other) {
          const target = picker.locator(`a[${site.languageAttribute}="${other}"]`);
          await target.click();
          await expect(page.locator('html')).toHaveAttribute('lang', other === 'zh' ? 'zh-CN' : other);
        }
      }
    });
  });
}

for (const language of languages) {
  test.describe(`${language} static HTML`, () => {
    test.use({ javaScriptEnabled: false, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    test('translated content and local images work without JavaScript', async ({ page }, testInfo) => {
      await openPage(page, language);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', site.url + (language === 'en' ? '' : language + '/'));
      if (site.picker) {
        const picker = page.locator(site.picker);
        await picker.locator('summary').click();
        await expect(picker.locator('a')).toHaveCount(site.languages.length);
        expect(await picker.locator(site.menu).evaluate(panelBounds)).toMatchObject({ inside: true, textFits: true });
      }
      if (site.picker) await page.locator(site.picker + ' > summary').click();
      await checkLayout(page, testInfo);
    });
  });
}

test('layout guard rejects overflow and clipped content', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openPage(page, 'en');
  await page.addStyleTag({ content: 'h1 { min-width: 2000px !important; }' });
  const report = await page.evaluate(measureLayout, { cards: site.cards });
  expect(report.violations.some(issue => ['outside viewport', 'text or control overflows', 'page overflows horizontally'].includes(issue.reason))).toBe(true);
});

if (site.notFound) test('custom 404 fits on a phone', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await openPage(page, 'en', '404.html');
  await checkLayout(page, testInfo);
  await page.locator('main a[href="/"]').click();
  await expect(page.locator('h1')).toContainText('Useful tools.');
});
