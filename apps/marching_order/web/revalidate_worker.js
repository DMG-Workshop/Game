// The site's one service worker, and all it does: every file the app asks
// for is checked with the server, every time.
//
// GitHub Pages lets a browser keep each file for ten minutes, and the app's
// code is always called main.dart.js, so after a deploy a reload could go on
// running the old game for that long. A hard refresh did not help either,
// because the code is fetched after the page itself has loaded. Through
// here, a file that has not changed comes back as a cheap "not modified" and
// one that has is fetched new. Nothing is kept for offline play.
//
// The page itself is left to the browser, which checks it on a reload, and
// which holds nothing in it that changes from one build to the next.

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.mode === 'navigate') return;
  if (new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(fetch(request, { cache: 'no-cache' }));
});
