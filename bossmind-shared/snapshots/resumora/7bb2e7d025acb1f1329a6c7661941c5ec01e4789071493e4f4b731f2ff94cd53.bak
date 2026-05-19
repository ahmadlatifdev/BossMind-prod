const CACHE = 'bossmind-shell-v1';
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(['./index.html','./config.js','./manifest.webmanifest','../../shared/styles.css','../../shared/app.js'])));
});
self.addEventListener('fetch', event => {
  event.respondWith(caches.match(event.request).then(res => res || fetch(event.request)));
});
