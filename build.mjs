import fs from 'node:fs/promises';
await fs.mkdir('dist',{recursive:true});await fs.cp('public','dist',{recursive:true});
for(const f of ['main.js','core.js','gis.js','api.js','queue.js','xlsx-tulis.js'])await fs.copyFile(`src/${f}`,`dist/${f}`);
await fs.copyFile('node_modules/@zxing/browser/umd/zxing-browser.min.js','dist/vendor/zxing-browser.min.js');
