// Reuses the original renderer and its tuning values; bundles D3 fully offline.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
require('./ets-loader.cjs');
const { ProfileConfig, paletteFor } = require('../entry/src/main/ets/domain/Models.ets');
const studio = process.env.DEVECO_STUDIO_HOME || 'F:/DevEco Studio';
const ts = require(path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const original = process.env.LIFEGRAPH_ORIGINAL_SOURCE || path.resolve(__dirname, '../../life-graph-main/src');
const locale = JSON.parse(fs.readFileSync(path.join(original, 'i18n/locales/zh.json'), 'utf8'));
function translation(key) { return key.split('.').reduce((value, part) => value?.[part], locale) || key; }
function load(file, imports = {}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(original, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => {
    if (!(name in imports)) throw new Error(`Unexpected graph dependency: ${name}`);
    return imports[name];
  } });
  return exports;
}
const { D3_SCRIPT } = load('components/graph/d3-script.ts');
const { GraphConfig } = load('components/graph/graph-config.ts');
const { getGraphHtml } = load('components/graph/graph-template.ts', {
  '@/components/graph/d3-script': { D3_SCRIPT }, '@/i18n': { t: translation }
});
const output = path.resolve(__dirname, '../entry/src/main/resources/rawfile/graph');
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(path.join(output, 'd3.min.js'), D3_SCRIPT);
for (const theme of ['forest', 'ocean', 'sunset', 'minimal']) for (const dark of [false, true]) {
  const profile = new ProfileConfig(); profile.themeKey = theme; profile.appearance = dark ? 'dark' : 'light';
  const colors = paletteFor(profile, dark);
  const palette = {
    paper: colors.paper, textMain: colors.text,
    textMuted: colors.muted, primary: colors.primary, primaryDark: colors.primary,
    secondary: '#C49A6C', secondaryLight: dark ? '#544A3D' : '#D9B896', secondaryDark: '#A67C52',
    borderLight: colors.border, accent: '#C97B6B', accentDark: '#A66355'
  };
  let html = getGraphHtml(palette, GraphConfig);
  html = html.replace(`<script>${D3_SCRIPT}</script>`, '<script src="d3.min.js"></script>');
  html = html.replace('<head>', `<head><script>
window.ReactNativeWebView={postMessage:function(message){
  if(window.nativeBridge){window.nativeBridge.postMessage(message);}
}};
</script>`);
  fs.writeFileSync(path.join(output, `${theme}-${dark ? 'dark' : 'light'}.html`), html);
}
console.log('Prepared 8 graph themes and shared offline D3 from original source.');
