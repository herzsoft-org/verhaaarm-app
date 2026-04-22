import 'notification_center.dart';
import 'push_status_probe.dart';

class _StubPushStatusProbe implements PushStatusProbe {
  @override
  Future<PushStatus> readStatus() async => PushStatus.unsupported;
}

PushStatusProbe createPushStatusProbeImpl() => _StubPushStatusProbe();