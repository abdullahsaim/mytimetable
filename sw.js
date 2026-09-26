// Cadence service worker: offline app shell, push notifications (even when the app is closed), notification clicks.
const CACHE = "cadence-v9";
const CORE = [
  "./", "./index.html", "./privacy.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png",
  "./vendor/fonts.css", "./vendor/supabase.js",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // live data (Supabase) is never cached

  if (req.mode === "navigate") {
    // Network first so updates arrive; fall back to the cached page offline.
    e.respondWith(
      fetch(req)
        .then((res) => { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); return res; })
        .catch(async () => (await caches.match(req, { ignoreSearch: true })) || caches.match("./index.html"))
    );
    return;
  }
  // Stale-while-revalidate for app files, fonts and libraries.
  e.respondWith(
    caches.open(CACHE).then(async (c) => {
      const hit = await c.match(req);
      const net = fetch(req).then((res) => { if (res.ok) c.put(req, res.clone()); return res; }).catch(() => hit);
      return hit || net;
    })
  );
});

// A notification sent by the server (reminder, Sunday summary, test)
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(
    self.registration.showNotification(d.title || "Cadence", {
      body: d.body || "",
      tag: d.tag || undefined,
      icon: "icon-192.png",
      badge: "icon-192.png",
      data: { url: d.url || "./" },
    })
  );
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const target = new URL((e.notification.data && e.notification.data.url) || "./", self.registration.scope).href;
  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(async (cs) => {
      const c = cs.find((x) => x.url.startsWith(self.registration.scope)) || cs[0];
      if (c) {
        if (target.includes("?tool=") && "navigate" in c) { try { await c.navigate(target); } catch { /* ignore */ } }
        return c.focus();
      }
      return self.clients.openWindow(target);
    })
  );
});
