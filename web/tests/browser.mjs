import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const systemChrome = process.platform === 'win32'
  ? [
      process.env.ProgramFiles && join(process.env.ProgramFiles, 'Google/Chrome/Application/chrome.exe'),
      process.env['ProgramFiles(x86)'] && join(process.env['ProgramFiles(x86)'], 'Google/Chrome/Application/chrome.exe'),
      process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'Google/Chrome/Application/chrome.exe'),
    ].find((candidate) => candidate && existsSync(candidate))
  : undefined;
const executablePath = process.env.CHROME_PATH || systemChrome;
const screenshots = process.env.SCREENSHOT_DIR
  ? resolve(process.env.SCREENSHOT_DIR)
  : await mkdtemp(join(tmpdir(), 'ox-inventory-browser-'));
await mkdir(screenshots, { recursive: true });

const browser = await chromium.launch({ ...(executablePath ? { executablePath } : {}), headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));

async function open(accept = true) {
  const url = new URL(process.env.NUI_URL || 'http://localhost:5173/');

  if (accept) url.searchParams.set('fixture', 'accept');
  else url.searchParams.delete('fixture');

  await page.goto(url.href);
  await page.locator('.inventory-slot').first().waitFor();
  await page.addStyleTag({ content: '#root { background: #20252c !important; }' });
}

const slot = (inventory, anchor) => page.locator(`[data-inventory="fixture-${inventory}"][data-slot="${anchor}"]`);

async function target(grid, cell) {
  const rect = await page.locator('.inventory-grid-content').nth(grid).locator(`[data-cell="${cell}"]`).boundingBox();

  assert(rect, 'destination cell is visible');

  return { x: rect.x + 20, y: rect.y + 20 };
}

async function drag(inventory, anchor, grid, cell, rotate = false) {
  const source = await slot(inventory, anchor).boundingBox();

  assert(source, 'source item is visible');

  await page.mouse.move(source.x + 30, source.y + 30);
  await page.mouse.down();
  await page.mouse.move(source.x + 45, source.y + 45, { steps: 4 });

  const destination = await target(grid, cell);

  await page.mouse.move(destination.x, destination.y, { steps: 12 });

  if (rotate) await page.keyboard.press('r');

  await page.locator('.inventory-placement').first().waitFor();

  if (rotate) {
    await page.waitForFunction(
      () =>
        new Set(
          [...document.querySelectorAll('.inventory-placement.valid')].map((element) => element.style.gridRow)
        ).size === 4
    );
  }
}

try {
  await open();
  assert.equal(await slot('player', 1).evaluate((element) => element.style.gridArea), '1 / 1 / span 2 / span 4');
  assert.equal(await page.locator('.inventory-grid-content').first().locator('.inventory-cell').count(), 33);
  await page.screenshot({ path: join(screenshots, 'initial.png') });
  await drag('player', 1, 1, 1, true);
  assert.equal(await page.locator('.inventory-placement.valid').count(), 8);
  const previewRows = await page
    .locator('.inventory-placement.valid')
    .evaluateAll((elements) => elements.map((element) => element.style.gridRow));

  assert.equal(new Set(previewRows).size, 4);
  await page.screenshot({ path: join(screenshots, 'rotated-preview.png') });
  await page.mouse.up();
  await slot('stash', 1).waitFor();
  assert.equal(await slot('player', 1).count(), 0);
  assert.equal(await slot('stash', 1).evaluate((element) => element.style.gridArea), '1 / 1 / span 4 / span 2');
  console.log('PASS drag R rotation previews eight cells and authoritative move retains 2x4 footprint');

  await page.getByRole('button', { name: 'Reclaim', exact: true }).click();
  await page.waitForFunction(() => !document.querySelector('.inventory-recovery'));
  assert.equal(await slot('player', 1).count(), 1);
  console.log('PASS recovery reclaim renders authoritative item and removes tray');

  await open();
  await drag('player', 1, 1, 5);
  assert.equal(await page.locator('.inventory-placement.invalid').count(), 2);
  await page.mouse.up();
  assert.equal(await slot('player', 1).count(), 1);
  assert.equal(await slot('stash', 5).count(), 0);
  console.log('PASS right-edge preview rejects placement and retains the source');

  await open(false);
  await drag('player', 1, 1, 1);
  assert.equal(await page.locator('.inventory-placement.valid').count(), 8);
  await page.mouse.up();
  await page.waitForFunction(() => document.querySelector('[aria-busy="true"]') === null);
  assert.equal(await slot('player', 1).count(), 1);
  assert.equal(await slot('stash', 1).count(), 0);
  console.log('PASS rejected placement retains original item and clears pending state');

  await open();
  await page.keyboard.down('Shift');
  await drag('player', 1, 1, 1);
  await page.mouse.up();
  await page.keyboard.up('Shift');
  await slot('stash', 1).waitFor();
  assert.match(await slot('player', 1).innerText(), /2x/);
  assert.match(await slot('stash', 1).innerText(), /2x/);
  console.log('PASS shift drag splits stack into two rectangles');
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.screenshot({ path: join(screenshots, '1280-split.png') });
  assert.deepEqual(errors, []);
  console.log('PASS no browser page errors');
  console.log(`Screenshots saved to ${screenshots}`);
} finally {
  await browser.close();
}
