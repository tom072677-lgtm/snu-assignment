self.addEventListener("install", (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open("assignment-app-v34").then((cache) => {
      return cache.addAll([
        "./",
        "./index.html",
        "./style.css",
        "./script.js",
        "./app.webmanifest",
        "./icon-192.png",
        "./icon-512.png"
      ]);
    })
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== "assignment-app-v34").map((k) => caches.delete(k)))
    ).then(() => clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request));
});

self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {};
  const title = data.title || "샤랍";
  const options = {
    body: data.body || "확인해주세요!",
    icon: data.icon || "./icon-192.png",
    badge: data.badge || "./icon-192.png",
    tag: data.tag || "sharap-alert",
    renotify: data.renotify !== false,
    requireInteraction: data.requireInteraction === true,
    data: data.data || {}
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = event.notification.data && event.notification.data.url
    ? event.notification.data.url
    : "./";
  event.waitUntil(clients.openWindow(url));
});

self.addEventListener("message", (event) => {
  const data = event.data;
  if (!data || data.type !== "LOCAL_NOTIFICATION") return;
  event.waitUntil(
    self.registration.showNotification(data.title || "샤랍", {
      body: data.body || "",
      icon: data.icon || "./icon-192.png",
      badge: data.badge || "./icon-192.png",
      tag: data.tag || "sharap-alert",
      renotify: true,
      requireInteraction: true,
      data: data.data || {},
    })
  );
});
