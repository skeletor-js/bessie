import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const baseURL = process.env.BESSIE_PROOF_URL || 'http://127.0.0.1:8787';
const output = new URL('../proof/', import.meta.url);
await mkdir(output, { recursive: true });

const browser = await chromium.launch({ headless: true });
const errors = [];
const userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

async function capture(width) {
  const page = await browser.newPage({ viewport: { width, height: 900 }, reducedMotion: 'no-preference', userAgent });
  const failed = [];
  page.on('requestfailed', request => {
    if (request.url().endsWith('/assets/bessie-opening.mp4') && request.failure()?.errorText === 'net::ERR_ABORTED') return;
    failed.push(`${request.method()} ${request.url()}: ${request.failure()?.errorText}`);
  });
  page.on('response', response => {
    if (response.status() >= 400) failed.push(`${response.status()} ${response.url()}`);
  });
  page.on('pageerror', error => errors.push(`${width}px: ${error.message}`));
  await page.addInitScript(() => {
    window.__BESSIE_SITE__ = { openingVideo: false, coldOpen: false, parallax: false };
    window.__copied = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: text => { window.__copied = text; return Promise.resolve(); } },
    });
  });
  await page.goto(baseURL, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.__BESSIE_LANDING__?.done === true);
  if (await page.locator('#site-opening').count()) throw new Error(`${width}px: disabled opening video was not removed`);
  await page.screenshot({ path: new URL(`landing-${width}.png`, output).pathname, fullPage: true });
  for (const id of ['top', 'surface', 'state', 'client', 'get']) {
    if (!await page.locator(`#${id}`).isVisible()) throw new Error(`${width}px: #${id} is not visible`);
  }
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  if (overflow > 1) throw new Error(`${width}px: horizontal overflow is ${overflow}px`);
  if (failed.length) throw new Error(`${width}px: failed requests\n${failed.join('\n')}`);

  const anchors = await page.locator('nav a[href^="#"]').evaluateAll(elements => elements.map(element => element.getAttribute('href')));
  for (const href of ['#top', '#surface', '#state', '#client']) {
    if (!anchors.includes(href)) throw new Error(`${width}px: missing navigation anchor ${href}`);
  }
  const repoLinks = await page.locator('[data-link="repo"]').evaluateAll(elements =>
    elements.map(element => ({ href: element.getAttribute('href'), rel: element.getAttribute('rel'), target: element.getAttribute('target') })),
  );
  if (repoLinks.some(link => link.href !== 'https://github.com/skeletor-js/bessie' || link.rel !== 'noopener' || link.target !== '_blank')) {
    throw new Error(`${width}px: repo CTA configuration is wrong`);
  }
  const releaseURL = 'https://github.com/skeletor-js/bessie/releases/download/v1.0.2/Bessie-1.0.2-23.zip';
  if (await page.locator('[data-link="download"]').evaluateAll((elements, expected) => elements.some(element =>
    element.getAttribute('href') !== expected || element.getAttribute('target') !== '_blank' || element.getAttribute('rel') !== 'noopener'
  ), releaseURL)) {
    throw new Error(`${width}px: release download CTA configuration is wrong`);
  }

  if (await page.locator('[data-copy-row]:visible').count() !== 2) {
    throw new Error(`${width}px: curl installer rows are not visible`);
  }
  if (await page.locator('[data-install]').evaluateAll(elements => elements.some(element => element.textContent !== 'curl -fsSL https://bessie.dev/install | sh'))) {
    throw new Error(`${width}px: curl installer command is wrong`);
  }

  const age = page.locator('.rr-age').first();
  const before = await age.textContent();
  await page.waitForTimeout(1150);
  if (await age.textContent() === before) throw new Error(`${width}px: relative age did not advance`);

  const install = await page.evaluate(async () => {
    const response = await fetch('/install');
    return { status: response.status, body: await response.text() };
  });
  if (install.status !== 200 || !/Bessie-1\.0\.2-23\.zip[\s\S]*codesign --verify[\s\S]*stapler validate[\s\S]*spctl --assess/.test(install.body)) {
    throw new Error(`${width}px: /install is not the verified build-23 installer`);
  }
  await page.close();
}

async function verifyFallbackAndWatchdog() {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, userAgent });
  await page.addInitScript(() => {
    window.__BESSIE_SITE__ = {
      openingVideo: false,
      coldOpen: false,
      parallax: false,
      installCmd: 'curl -fsSL https://bessie.dev/install | sh',
      downloadUrl: 'https://example.invalid/Bessie.zip',
    };
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined });
    document.execCommand = () => false;
  });
  await page.goto(baseURL, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.__BESSIE_LANDING__?.done === true);
  await page.locator('[data-copybtn]').first().click();
  await page.waitForFunction(() => document.querySelector('[data-copylabel]')?.textContent === 'Press ⌘C');

  await page.evaluate(() => clearInterval(window.__BESSIE_LANDING__.timer));
  await page.waitForFunction(() => window.__BESSIE_LANDING__?.loopDead === true, null, { timeout: 5000 });
  const hidden = await page.locator('[data-rise], [data-reveal], [data-ladder], [data-arrive], [data-term] > *, [data-stagger] > *').evaluateAll(elements =>
    elements.filter(element => Number(getComputedStyle(element).opacity) < 0.99).map(element => element.outerHTML.slice(0, 160)),
  );
  if (hidden.length) throw new Error(`watchdog left animated elements hidden:\n${hidden.join('\n')}`);
  await page.close();
}

async function verifyReducedMotion() {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce', userAgent });
  page.on('pageerror', error => errors.push(`reduced motion: ${error.message}`));
  await page.goto(baseURL, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.__BESSIE_LANDING__?.done === true);
  for (const selector of ['[data-o="mark"]', '[data-o="tag"]', '[data-o="cta"]', '[data-o="ver"]']) {
    const opacity = Number(await page.locator(selector).evaluate(element => getComputedStyle(element).opacity));
    if (opacity < 0.99) throw new Error(`reduced motion left ${selector} at opacity ${opacity}`);
  }
  for (const section of await page.locator('section').all()) {
    await section.scrollIntoViewIfNeeded();
  }
  const hidden = await page.locator('[data-rise], [data-reveal], [data-ladder]').evaluateAll(elements =>
    elements.filter(element => Number(getComputedStyle(element).opacity) < 0.99).length,
  );
  if (hidden) throw new Error(`reduced motion left ${hidden} animated elements hidden`);
  await page.screenshot({ path: new URL('reduced-motion-1280.png', output).pathname, fullPage: true });
  await page.close();
}

async function verifyOpeningVideo() {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, reducedMotion: 'no-preference', userAgent });
  await page.goto(baseURL, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const video = document.querySelector('#site-opening');
    return video && video.currentTime > 0.1;
  }, null, { timeout: 5000 });
  await page.waitForFunction(() => !document.querySelector('#site-opening'), null, { timeout: 7000 });
  await page.waitForFunction(() => window.__BESSIE_LANDING__?.done === true);
  await page.close();
}

try {
  await verifyOpeningVideo();
  await capture(390);
  await capture(1280);
  await capture(1440);
  await verifyFallbackAndWatchdog();
  await verifyReducedMotion();
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(`visual proof: ok (${baseURL}; 390, 1280, 1440, opening video, copy/fallback, CTA config, ages/watchdog, /install, reduced motion)`);
} finally {
  await browser.close();
}
