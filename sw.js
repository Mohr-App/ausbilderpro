const CACHE = 'ausbilderpro-v235';
const ASSETS = [
  './AusbilderPro.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  'https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Sora:wght@300;400;600;700&display=swap',
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js',
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore-compat.js',
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-storage-compat.js'
];

// Install: pre-cache assets als Offline-Fallback
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(ASSETS.map(u => new Request(u, {mode: 'no-cors'}))))
      .catch(() => {})
  );
  self.skipWaiting();
});

// Activate: alte Caches löschen
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch: NETWORK-FIRST – immer neueste Version holen, Cache nur als Fallback
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;

  // Firebase/Firestore API-Calls niemals cachen
  const url = e.request.url;
  if (url.includes('firestore.googleapis.com') ||
      url.includes('identitytoolkit.googleapis.com') ||
      url.includes('securetoken.googleapis.com') ||
      url.includes('firebasestorage.googleapis.com')) {
    return;
  }

  e.respondWith(
    fetch(e.request)
      .then(res => {
        // Erfolgreiche Antwort → im Cache aktualisieren
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      })
      .catch(() => {
        // Offline → aus Cache liefern
        return caches.match(e.request);
      })
  );
});
