import 'notification_center.dart';
import 'push_status_probe_stub.dart'
if (dart.library.js_interop) 'push_status_probe_web.dart';

abstract class PushStatusProbe {
  Future<PushStatus> readStatus();
}

PushStatusProbe createPushStatusProbe() => createPushStatusProbeImpl();