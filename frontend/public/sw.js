const CACHE_NAME = 'careaudit-shell-v6';
const APP_SHELL = ['/', '/index.html', '/manus-routes.json', '/checklistData.json', '/manifest.webmanifest'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  const pathname = new URL(event.request.url).pathname;
  if (pathname === '/sw.js' || pathname.startsWith('/api/')) return;
  const isNavigation = event.request.mode === 'navigate' || pathname === '/' || pathname === '/index.html';
  const isRefreshable = isNavigation || pathname === '/checklistData.json' || pathname === '/manus-routes.json';

  if (isRefreshable) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(event.request);
        if (response.ok) await cache.put(event.request, response.clone());
        return response;
      } catch (error) {
        const cached = await caches.match(event.request);
        const fallback = isNavigation && !cached ? await caches.match('/index.html') : null;
        if (cached || fallback) return cached || fallback;
        throw error;
      }
    })());
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
      }
      return response;
    }))
  );
});
