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
  const actions =
    data.supportsActions === 'true' &&
    data.actionSet === 'LIVE_EVENT_REACTIONS'
      ? [
          { action: 'PROST', title: '🍻 Prost!' },
          { action: 'ICH_KOMME', title: '🏃 Ich komme!' },
        ]
      : undefined;

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      data,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-maskable-192.png',
      tag: data.notificationId || undefined,
      renotify: false,
      actions,
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data || {};

  if (event.action === 'PROST' || event.action === 'ICH_KOMME') {
    event.waitUntil(openLiveEventFallback(data, event.action));
    return;
  }

  let targetUrl = '/';
  switch ((data.clickTarget || '').toString()) {
    case 'HOME_LIVE_EVENTS':
      targetUrl = '/home';
      break;
    case 'ACTIONS_ARBEITSAUFTRAEGE':
      targetUrl = '/tasks';
      break;
    case 'ACTIONS_BEIHAENGUNG':
      targetUrl = '/my-fines';
      break;
    case 'FINE_SUGGESTIONS':
      targetUrl = '/office/fine-suggestions';
      break;
    default:
      if (data.notificationId) {
        targetUrl = '/notifications';
      }
      break;
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

function liveEventIdFromData(data) {
  if (data.reactionEndpoint) {
    const match = data.reactionEndpoint
      .toString()
      .match(/\/live-events\/([^/]+)\/reactions\/\{type\}/);
    if (match) return match[1];
  }

  return data.liveEventId || data.liveEventID || data.eventId || data.id;
}

function liveEventTargetUrl(data, action) {
  const id = liveEventIdFromData(data);
  if (!id) return '/live-events';
  return `/live-events/${encodeURIComponent(id)}?reaction=${encodeURIComponent(action)}`;
}

function openLiveEventFallback(data, action) {
  const targetUrl = liveEventTargetUrl(data, action);
  return clients
    .matchAll({ type: 'window', includeUncontrolled: true })
    .then((clientList) => {
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
    });
}
