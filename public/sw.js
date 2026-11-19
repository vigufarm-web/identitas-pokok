const CACHE='identitas-pokok-v1';const FILES=['./','./index.html','./style.css','./main.js','./core.js','./gis.js','./api.js','./queue.js','./xlsx-tulis.js','./manifest.webmanifest','./vendor/leaflet.js','./vendor/leaflet.css','./vendor/zxing-browser.min.js'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES))));
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==self.location.origin)return;e.respondWith(fetch(e.request).then(r=>{if(r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));}return r;}).catch(()=>caches.match(e.request)));});
