import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/charging_status_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub(this.energyWh);

  final int energyWh;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: progressResponse(energyWh: energyWh),
        statusCode: 200,
      ),
    );
  }
}

ChargingSession _session() {
  final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

  return ChargingSession.resumed(
    chargeBox: box,
    connector: box.connectors.single,
    now: DateTime(2026),
  );
}

void main() {
  /// `POST /list-chargerbox` tidak membawa sesi yang sedang berjalan,
  /// jadi tidak ada angka awal untuk dipasang — layar mulai dari nol.
  testWidgets('tanpa scope, energi mulai dari nol', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargingStatusPage(session: _session()),
      ),
    );
    await tester.pump();

    expect(find.text('0,000 kWh'), findsOneWidget);
    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  testWidgets('polling /progress pertama mengisi angkanya', (tester) async {
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(127))),
    );

    await tester.pumpWidget(
      ChargingScope(
        repository: repo,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChargingStatusPage(session: _session()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('0,000 kWh'), findsOneWidget);

    // Satu putaran polling.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('0,127 kWh'), findsOneWidget);
  });
}
