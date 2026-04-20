self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open("assignment-app-v2").then((cache) => {
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

self.addEventListener("fetch", (event) => {
  event.respondWith(
    caches.match(event.request).then((response) => response || fetch(event.request))
  );
});
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {};
  const title = data.title || "SNU 과제 알림";
  const options = {
    body: data.body || "확인해주세요!",
    icon: "./icon-192.png"
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow("/"));
});