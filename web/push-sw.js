self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  console.debug('[push-sw] PUSH EVENT RECEIVED', event);

  let payload = {};

  try {
    payload = event.data ? event.data.json() : {};
    console.debug('[push-sw] parsed payload', payload);
  } catch (_) {
    debugPush('push payload JSON parse failed; falling back to text body');
    payload = {
      title: 'Notification',
      body: event.data ? event.data.text() : '',
    };
  }

  const title = payload.title || 'Notification';
  const body = payload.body || '';
  const data = notificationDataFromPayload(payload);
  const actions = reactionActionsForData(data);

  const options = {
    body,
    data,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-maskable-192.png',
    tag: data.notificationId || undefined,
    renotify: false,
  };

  if (actions.length > 0) {
    options.actions = actions;
  }

  event.waitUntil(
    self.registration.showNotification(title, options).catch((err) => {
      debugPush(`showNotification failed: ${err && err.message ? err.message : err}`);
      if (options.actions) {
        const fallbackOptions = { ...options };
        delete fallbackOptions.actions;
        return self.registration.showNotification(title, fallbackOptions);
      }
      throw err;
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data || {};

  if (event.action === 'PROST' || event.action === 'ICH_KOMME') {
    event.waitUntil(handleLiveEventActionClick(data, event.action));
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

function notificationDataFromPayload(payload) {
  if (payload && payload.data && typeof payload.data === 'object') {
    return payload.data;
  }

  if (!payload || typeof payload !== 'object') return {};

  const data = {};
  for (const key of [
    'notificationId',
    'type',
    'notificationType',
    'clickTarget',
    'liveEventId',
    'supportsActions',
    'actionSet',
    'reactionEndpoint',
    'reactionTypes',
  ]) {
    if (payload[key] !== undefined && payload[key] !== null) {
      data[key] = payload[key];
    }
  }
  return data;
}

function reactionActionsForData(data) {
  if (
    data.supportsActions !== 'true' ||
    data.actionSet !== 'LIVE_EVENT_REACTIONS'
  ) {
    return [];
  }

  const supported = (data.reactionTypes || '')
    .toString()
    .split(',')
    .map((type) => type.trim());
  if (!supported.includes('PROST') || !supported.includes('ICH_KOMME')) {
    return [];
  }

  const maxActions =
    self.Notification && Number.isFinite(self.Notification.maxActions)
      ? self.Notification.maxActions
      : 0;
  if (maxActions < 2) {
    debugPush('notification actions unsupported; showing notification without actions');
    return [];
  }

  return [
    { action: 'PROST', title: '🍻 Prost!' },
    { action: 'ICH_KOMME', title: '🏃 Ich komme!' },
  ];
}

function liveEventTargetUrl(data, action) {
  const id = liveEventIdFromData(data);
  if (!id) return '/live-events';
  return `/live-events/${encodeURIComponent(id)}?reaction=${encodeURIComponent(action)}`;
}

function liveEventViewUrl(data) {
  const id = liveEventIdFromData(data);
  if (!id) return '/live-events';
  return `/live-events/${encodeURIComponent(id)}`;
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

function handleLiveEventActionClick(data, action) {
  const fallbackUrl = liveEventTargetUrl(data, action);
  const message = JSON.stringify({
    type: 'VERHAAARM_LIVE_EVENT_REACTION_ACTION',
    action,
    data,
  });

  return clients
    .matchAll({ type: 'window', includeUncontrolled: true })
    .then((clientList) => {
      const client =
        clientList.find((item) => item.focused) ||
        clientList.find((item) => item.visibilityState === 'visible') ||
        clientList[0];

      if (!client) {
        if (clients.openWindow) return clients.openWindow(fallbackUrl);
        return undefined;
      }

      client.postMessage(message);

      if ('navigate' in client) {
        try {
          const navigation = client.navigate(fallbackUrl);
          if (navigation && typeof navigation.then === 'function') {
            return navigation.then((navigatedClient) => {
              if (navigatedClient && 'focus' in navigatedClient) {
                return navigatedClient.focus();
              }
              if ('focus' in client) return client.focus();
              return undefined;
            });
          }
        } catch (err) {
          debugPush(`live event action navigate failed: ${err && err.message ? err.message : err}`);
        }
      }

      if ('focus' in client) return client.focus();
      return undefined;
    });
}

function debugPush(message) {
  try {
    console.debug(`[push-sw] ${message}`);
  } catch (_) {}
}
