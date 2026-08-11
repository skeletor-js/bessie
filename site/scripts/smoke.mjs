import fs from 'node:fs';

const publicFile = path => new URL(`../public/${path}`, import.meta.url);
const html = fs.readFileSync(publicFile('index.html'), 'utf8');
const css = fs.readFileSync(publicFile('styles.css'), 'utf8');
const main = fs.readFileSync(publicFile('main.js'), 'utf8');
const config = fs.readFileSync(publicFile('config.js'), 'utf8');

for (const id of ['top', 'surface', 'state', 'client', 'get']) {
  if (!html.includes(`id="${id}"`)) throw new Error(`missing #${id}`);
}
if (!/<title>[^<]*every agent, one window/i.test(html)) throw new Error('title missing');
for (const bad of ['React', 'dc-runtime', 'sc-camel', 'ref="{{']) {
  if (`${html}\n${css}\n${main}`.includes(bad)) throw new Error(`production leak: ${bad}`);
}
for (const file of [
  'styles.css', 'config.js', 'main.js', 'assets/favicon.png', 'assets/og.png',
  'assets/bessie-opening.mp4',
  'assets/fonts/phosphor-thin.woff2', 'assets/fonts/phosphor-fill.woff2',
]) {
  if (!fs.existsSync(publicFile(file))) throw new Error(`missing ${file}`);
}
for (const file of ['assets/marks/claude.svg', 'assets/marks/codex.svg', 'assets/marks/amp.svg']) {
  if (fs.existsSync(publicFile(file))) throw new Error(`third-party agent mark remains: ${file}`);
}
if ((css.match(/\.ph-(?:thin|fill)\.ph-[\w-]+::?before/g) || []).length > 22) {
  throw new Error('Phosphor selector dump was not pruned');
}
if (!main.includes('T = [[1,0,.58') || !main.includes('[4,1,.08,2.7,-.19]')) {
  throw new Error('cowprint twelve-term field is incomplete');
}
if (!/<video[^>]*id="site-opening"[^>]*autoplay[^>]*muted[^>]*playsinline/.test(html)) {
  throw new Error('site opening video is not configured for muted inline autoplay');
}
if (!config.includes('openingVideo:true') || !config.includes('coldOpen:false')) {
  throw new Error('site opening video must replace the legacy scripted cold open');
}
if (!main.includes('finishOpening') || !css.includes('#site-opening.is-done') || !css.includes('prefers-reduced-motion: reduce')) {
  throw new Error('site opening video is missing its fail-open or reduced-motion behavior');
}
if (!html.includes('data-copy-row') || !html.includes('data-install') || !config.includes("installCmd:'curl -fsSL https://bessie.dev/install | sh'")) {
  throw new Error('curl installer UI is missing');
}
if (!config.includes("downloadUrl:'https://github.com/skeletor-js/bessie/releases/download/v1.0.2/Bessie-1.0.2-23.zip'")) {
  throw new Error('public release download URL is missing');
}
for (const stale of [
  'Point it at the Herdr you already run.', 'it starts nothing',
  'Answer from the drop-down', 'Approving sends', 'Draft 0.1.0 release notes',
]) {
  if (html.includes(stale)) throw new Error(`stale V1 claim remains: ${stale}`);
}

console.log('static smoke: ok');
