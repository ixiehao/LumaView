import { test as base, expect } from '@playwright/test';
import site from '../website-test.config.mjs';

export { expect, site };
const selected = process.env.SITE_TEST_LANGUAGE;
if (selected && !site.languages.includes(selected)) throw Error(`Unsupported test language: ${selected}`);
export const languages = selected ? [selected] : site.languages;
export const viewports = [
  [320, 568], [360, 780], [375, 812], [390, 844], [430, 932],
  [600, 900], [768, 1024], [1024, 900], [1280, 900], [1440, 1000],
  [740, 360], [844, 390],
  ...site.breakpoints.flatMap(width => [[width, 900], [width + 1, 900]])
].filter((size, index, all) => all.findIndex(other => other.join() === size.join()) === index)
  .map(([width, height]) => ({ width, height }));

export const test = base.extend({
  page: async ({ page, baseURL }, use) => {
    const origin = new URL(baseURL).origin;
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => {
      if (new URL(response.url()).origin === origin && response.status() >= 400) errors.push(`${response.status()} ${response.url()}`);
    });
    await page.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
    await use(page);
    expect(errors, 'Local resources and browser runtime').toEqual([]);
  }
});

export async function openPage(page, language, route = language === 'en' ? './' : `${language}/`) {
  const response = await page.goto(route);
  expect(response.status()).toBe(200);
  await expect(page.locator('h1')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', language === 'zh' ? 'zh-CN' : language);
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map(image => {
      image.loading = 'eager';
      return image.decode().catch(() => {});
    }));
  });
  expect(await page.evaluate(() => innerWidth), 'Honor the mobile device-width viewport').toBe(page.viewportSize().width);
  expect(await page.locator('body').innerText()).not.toMatch(/\{\{[a-zA-Z]\w*\}\}/);
  await page.mouse.move(0, 0);
}

// Read actual geometry, including children clipped by overflow:hidden on an ancestor.
// Only intentional horizontal scroll containers and explicit text ellipses are exempt.
export function measureLayout(options) {
  const root = options?.root ? document.querySelector(options.root) : document.body;
  const violations = [];
  const label = element => element.id ? `#${element.id}` : `${element.tagName.toLowerCase()}.${String(element.className).trim().replace(/\s+/g, '.')} ${element.textContent.trim().slice(0, 55)}`;
  const visible = element => {
    if (!element.getClientRects().length || getComputedStyle(element).visibility === 'hidden' || element.closest('[aria-hidden="true"],svg')) return false;
    for (let ancestor = element.parentElement; ancestor; ancestor = ancestor.parentElement) {
      if (ancestor.tagName === 'DETAILS' && !ancestor.open && !ancestor.querySelector(':scope > summary')?.contains(element)) return false;
    }
    return true;
  };
  const scroller = element => {
    for (let ancestor = element.parentElement; ancestor && ancestor !== document.body; ancestor = ancestor.parentElement) {
      if (['auto', 'scroll'].includes(getComputedStyle(ancestor).overflowX) && ancestor.scrollWidth > ancestor.clientWidth + 2) return ancestor;
    }
    return null;
  };
  for (const element of root.querySelectorAll('h1,h2,h3,h4,p,li,a,button,summary,label,img,figcaption')) {
    if (!visible(element)) continue;
    const rect = element.getBoundingClientRect();
    const css = getComputedStyle(element);
    if (element.matches('.skip-link,.sr-only,.visually-hidden') && element !== document.activeElement) continue;
    if ((rect.left < -2 || rect.right > innerWidth + 2) && !scroller(element)) violations.push({ element: label(element), reason: 'outside viewport', left: rect.left, right: rect.right });
    if (element.clientWidth && element.scrollWidth > element.clientWidth + 2 && !['auto', 'scroll'].includes(css.overflowX) && css.textOverflow !== 'ellipsis') violations.push({ element: label(element), reason: 'text or control overflows', width: element.clientWidth, content: element.scrollWidth });
    const container = options?.cards && element.closest(options.cards);
    if (container && container !== element && !scroller(element)) {
      const bounds = container.getBoundingClientRect();
      if (rect.left < bounds.left - 2 || rect.right > bounds.right + 2 || rect.bottom > bounds.bottom + 2) violations.push({ element: label(element), reason: 'outside component', component: label(container) });
    }
    if (element.tagName === 'IMG') {
      if (!element.complete || !element.naturalWidth) violations.push({ element: label(element), reason: 'image failed to decode', source: element.getAttribute('src') });
      else if (css.objectFit === 'fill' && Math.abs(rect.width / rect.height / (element.naturalWidth / element.naturalHeight) - 1) > .04) violations.push({ element: label(element), reason: 'image aspect ratio distorted' });
    }
  }
  const controls = [...root.querySelectorAll('a,button,summary')].filter(element => visible(element) && !scroller(element) && !(element.matches('.skip-link') && element !== document.activeElement));
  for (let i = 0; i < controls.length; i++) for (let j = i + 1; j < controls.length; j++) {
    const a = controls[i], b = controls[j];
    if (a.contains(b) || b.contains(a)) continue;
    const overlaps = [...a.getClientRects()].some(x => [...b.getClientRects()].some(y => Math.min(x.right, y.right) - Math.max(x.left, y.left) > 2 && Math.min(x.bottom, y.bottom) - Math.max(x.top, y.top) > 2));
    if (overlaps) violations.push({ element: label(a), other: label(b), reason: 'overlapping controls' });
  }
  for (const selector of options?.uniform || []) {
    const styles = [...root.querySelectorAll(selector)].filter(visible).map(element => {
      const css = getComputedStyle(element);
      return JSON.stringify([css.padding, css.borderRadius, css.fontSize]);
    });
    if (new Set(styles).size > 1) violations.push({ element: selector, reason: 'inconsistent component styles' });
  }
  for (const grid of options?.grids || []) {
    const element = document.querySelector(grid.selector);
    if (!element) { violations.push({ element: grid.selector, reason: 'missing responsive grid' }); continue; }
    const expected = grid.columns.find(([max]) => innerWidth <= max)[1];
    const actual = getComputedStyle(element).gridTemplateColumns.split(' ').length;
    if (actual !== expected) violations.push({ element: grid.selector, reason: 'wrong responsive column count', expected, actual });
  }
  if (document.documentElement.scrollWidth > innerWidth + 1) violations.push({ reason: 'page overflows horizontally' });
  return { language: document.documentElement.lang, viewport: [innerWidth, innerHeight], violations };
}

export async function checkLayout(page, testInfo, extra = {}) {
  const report = await page.evaluate(measureLayout, { cards: site.cards, uniform: site.uniform, grids: site.grids, ...extra });
  await testInfo.attach('layout', { body: Buffer.from(JSON.stringify(report, null, 2)), contentType: 'application/json' });
  expect(report.violations, JSON.stringify(report.violations, null, 2)).toEqual([]);
}

export function panelBounds(element) {
  const rect = element.getBoundingClientRect();
  return { inside: rect.left >= -1 && rect.top >= -1 && rect.right <= innerWidth + 1 && rect.bottom <= innerHeight + 1, textFits: element.scrollWidth <= element.clientWidth + 2, rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }, viewport: [innerWidth, innerHeight] };
}
