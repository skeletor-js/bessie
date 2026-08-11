import fs from 'node:fs';

const publicFile = path => new URL(`../public/${path}`, import.meta.url);
const html = fs.readFileSync(publicFile('index.html'), 'utf8');
const css = fs.readFileSync(publicFile('styles.css'), 'utf8');
const main = fs.readFileSync(publicFile('main.js'), 'utf8');
const config = fs.readFileSync(publicFile('config.js'), 'utf8');

for (const id of ['top', 'surface', 'state', 'get']) {
  if (!html.includes(`id="${id}"`)) throw new Error(`missing #${id}`);
}
if (!/<title>[^<]*every agent, one window/i.test(html)) throw new Error('title missing');
for (const bad of ['React', 'dc-runtime', 'sc-camel', 'ref="{{']) {
  if (`${html}\n${css}\n${main}`.includes(bad)) throw new Error(`production leak: ${bad}`);
}
for (const file of [
  'styles.css', 'config.js', 'main.js', 'assets/bessie-logo.svg', 'assets/favicon.png', 'assets/og.png',
  'assets/bessie-opening.mp4',
  'assets/fonts/phosphor-thin.woff2', 'assets/fonts/phosphor-fill.woff2',
]) {
  if (!fs.existsSync(publicFile(file))) throw new Error(`missing ${file}`);
}
if ((html.match(/<img class="bessie-logo" src="\/assets\/bessie-logo\.svg" alt="">/g) || []).length !== 5) {
  throw new Error('current Bessie logo is missing from a branded site surface');
}
if ((html.match(/ph-fill ph-cow/g) || []).length !== 1 || !/<i id="cow-probe"[^>]*ph-fill ph-cow/.test(html)) {
  throw new Error('legacy cow glyph remains visible outside the animation probe');
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
  'Step one', 'Step two', 'Step three', 'Step four', 'Step five',
  'It never owns your live work.', 'Settled ·', 'oldest 2m',
  'panes · workspaces · projects · commands',
  'All herds', 'All workspaces', 'class="rr-age"', 'id="client"',
  'Run six coding agents', 'spend half the day', 'Any pane, three keystrokes.',
  'so you never act in the wrong repo', 'so you never open the wrong',
  'data-fit="1180x815"', 'bessie — the herd', 'class="topbar"', 'class="wb-tab',
  'claude · bessie / dev / theme', 'width:100%;max-width:760px',
  '⌘↩ alternate', 'Prove direct write ordering',
]) {
  if (html.includes(stale)) throw new Error(`stale V1 claim remains: ${stale}`);
}
for (const current of [
  'The siderail tells you where to look.',
  'Needs you · 2', 'Working · 2', 'Done · 2', 'Idle · 1', 'Unknown · 1',
  'panes · workspaces · projects · herds · commands',
  '2 need you · 2 working', '1 elsewhere',
  'data-fit="1180x740"', 'claude · local · bessie · dev',
  'Verify terminal input', 'Run release checks', 'width:312px',
  '<span>Done</span><strong>4', '<span>Idle</span><strong>3', '<span>Unknown</span><strong>1',
]) {
  if (!html.includes(current)) throw new Error(`current product story is missing: ${current}`);
}
if ((html.match(/class="zen-state(?: is-selected)?"/g) || []).length !== 8) {
  throw new Error('Zen awareness rail does not match the current eight-row fixture');
}
if ((html.match(/class="rail-row menu-row(?: is-highlighted)?"/g) || []).length !== 4) {
  throw new Error('menu bar fixture does not match the current four-row layout');
}

console.log('static smoke: ok');
