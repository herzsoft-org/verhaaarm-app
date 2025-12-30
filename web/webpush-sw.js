self.addEventListener('push', function (event) {
  event.waitUntil((async () => {
    let data = {};
    try {
      data = event.data ? event.data.json() : {};
    } catch (e) {
      try {
        data = event.data ? JSON.parse(event.data.text()) : {};
      } catch (_) {
        data = {};
      }
    }

    const title = (data && data.title) ? data.title : 'Notification';
    const body = (data && data.body) ? data.body : '';
    const notificationId = data.notificationId || null;
    const type = data.type || null;
    const extra = data.data || {};

    const options = {
      body,
      data: { notificationId, type, extra },
    };

    await self.registration.showNotification(title, options);
  })());
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();

  event.waitUntil((async () => {
    const allClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of allClients) {
      if ('focus' in c) return c.focus();
    }
    if (clients.openWindow) return clients.openWindow('/');
  })());
});
