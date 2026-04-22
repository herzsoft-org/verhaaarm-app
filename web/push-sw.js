self.addEventListener('push', (event) => {
  let payload = {};

  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {
      title: 'Notification',
      body: event.data ? event.data.text() : '',
    };
  }

  const title = payload.title || 'Notification';
  const body = payload.body || '';
  const data = payload.data || {};

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      data,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-maskable-192.png',
      tag: data.notificationId || undefined,
      renotify: false,
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data || {};

  let targetUrl = '/';
  if (data.notificationId) {
    targetUrl = '/notifications';
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          try {
            client.navigate(targetUrl);
          } catch (_) {}
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});