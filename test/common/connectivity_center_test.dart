import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verhaaarm/common/connectivity/connectivity_center.dart';

class _AlwaysOfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Future.error(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'offline',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
    'background failures start a fresh grace period only after resume',
    (tester) async {
      final center = ConnectivityCenter.I;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = _AlwaysOfflineAdapter();

      center.setAppForeground(false);
      center.reportFailure(dio);

      await tester.pump(const Duration(seconds: 20));
      expect(center.isReachable, isTrue);

      center.setAppForeground(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(center.isReachable, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(center.isReachable, isFalse);

      center.setAppForeground(false);
      expect(center.isReachable, isTrue);
    },
  );
}
