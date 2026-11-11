const { chromium } = require('playwright-core');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const fs = require('node:fs');

const root = path.resolve(__dirname, '..');
const template = pathToFileURL(path.join(__dirname, 'store-screenshot.html')).href;
const variants = [
  { platform: 'iphone', width: 1206, height: 2622, folder: 'iPhone' },
  { platform: 'ipad', width: 2048, height: 2732, folder: 'iPad' },
];
const names = ['01-podcast-santa-luzia.png', '02-episodios.png', '03-ouca-do-seu-jeito.png'];

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--allow-file-access-from-files'],
  });
  try {
    for (const variant of variants) {
      const page = await browser.newPage({
        viewport: { width: variant.width, height: variant.height },
        deviceScaleFactor: 1,
      });
      const folder = path.join(root, 'Screenshots', variant.folder);
      fs.mkdirSync(folder, { recursive: true });
      for (let concept = 1; concept <= 3; concept++) {
        await page.goto(`${template}?platform=${variant.platform}&concept=${concept}`);
        await page.locator('img').evaluateAll(images => Promise.all(images.map(image => image.decode())));
        const output = path.join(folder, names[concept - 1]);
        await page.screenshot({ path: output });
        console.log(`${variant.platform} ${concept}: ${output}`);
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
