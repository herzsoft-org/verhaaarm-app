// Inject into flutter_service_worker.js (or concat at end)

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    try { data = { body: event.data ? event.data.text() : '' }; } catch (_) {}
  }

  const title =
    data.title ||
    data.notification?.title ||
    'New notification';

  const options = {
    body: data.body || data.notification?.body || '',
    data: data.data || data,
    icon: data.icon || '/icons/Icon-192.png',
    badge: data.badge || '/icons/Icon-192.png',
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification?.data && event.notification.data.url) ? event.notification.data.url : '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
