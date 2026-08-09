import fs from 'node:fs';

const publicFile = path => new URL(`../public/${path}`, import.meta.url);
const html = fs.readFileSync(publicFile('index.html'), 'utf8');
const css = fs.readFileSync(publicFile('styles.css'), 'utf8');
const main = fs.readFileSync(publicFile('main.js'), 'utf8');

for (const id of ['top', 'surface', 'state', 'client', 'get']) {
  if (!html.includes(`id="${id}"`)) throw new Error(`missing #${id}`);
}
if (!/<title>[^<]*every agent, one window/i.test(html)) throw new Error('title missing');
for (const bad of ['React', 'dc-runtime', 'sc-camel', 'ref="{{']) {
  if (`${html}\n${css}\n${main}`.includes(bad)) throw new Error(`production leak: ${bad}`);
}
for (const file of [
  'styles.css', 'config.js', 'main.js', 'assets/favicon.png', 'assets/og.png',
  'assets/fonts/phosphor-thin.woff2', 'assets/fonts/phosphor-fill.woff2',
  'assets/marks/claude.svg', 'assets/marks/codex.svg', 'assets/marks/amp.svg',
]) {
  if (!fs.existsSync(publicFile(file))) throw new Error(`missing ${file}`);
}
if ((css.match(/\.ph-(?:thin|fill)\.ph-[\w-]+::?before/g) || []).length > 22) {
  throw new Error('Phosphor selector dump was not pruned');
}
if (!main.includes('T = [[1,0,.58') || !main.includes('[4,1,.08,2.7,-.19]')) {
  throw new Error('cowprint twelve-term field is incomplete');
}

console.log('static smoke: ok');
