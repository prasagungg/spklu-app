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
import 'package:kossotrik/widgets/battery_gauge.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub(this.charged);

  final double charged;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: ongoingKwhResponse(charged: charged, status: 3),
        statusCode: 200,
      ),
    );
  }
}

/// Sesi dengan orderId — tanpa itu halaman status tidak menanyakan
/// apa pun, karena semua endpoint pengisian berkunci order.
ChargingSession _session({String orderId = 'ORDER-1'}) {
  final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

  return ChargingSession(
    chargeBox: box,
    connector: box.connectors.single,
    sessionCode: '29',
    reference: '81067',
    createdAt: DateTime(2026),
    orderId: orderId,
  );
}

void main() {
  /// Daftar charge box tidak membawa sesi yang sedang berjalan, jadi
  /// tidak ada angka awal untuk dipasang — layar mulai dari nol.
  testWidgets('tanpa scope, energi mulai dari nol', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargingStatusPage(session: _session()),
      ),
    );
    await tester.pump();

    expect(find.text('0 kWh'), findsOneWidget);
    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  testWidgets('polling ongoing-kwh pertama mengisi angkanya', (tester) async {
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(0.127))),
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
    expect(find.text('0 kWh'), findsOneWidget);

    // Satu putaran polling.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('0,127 kWh'), findsOneWidget);
  });

  /// Sesi yang dilanjutkan dari daftar charge box tidak membawa
  /// orderId, jadi tidak ada yang bisa ditanyakan.
  testWidgets('sesi tanpa orderId tidak menanyakan apa pun', (tester) async {
    final stub = _Stub(0.5);
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(stub)),
    );

    await tester.pumpWidget(
      ChargingScope(
        repository: repo,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChargingStatusPage(session: _session(orderId: '')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Jatuh ke simulasi lokal, bukan angka dari backend.
    expect(find.text('0,500 kWh'), findsNothing);
  });

  /// Tinggi cairan baterai = energi tersalur dibagi kWh yang dipesan.
  /// `ongoingKwhResponse` memesan 10 kWh.
  testWidgets('baterai terisi sesuai porsi kWh yang tersalur', (tester) async {
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(1))),
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
    expect(tester.widget<BatteryGauge>(find.byType(BatteryGauge)).fill, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // 1 kWh dari 10 kWh yang dipesan.
    expect(tester.widget<BatteryGauge>(find.byType(BatteryGauge)).fill, 0.1);
  });

  /// Charger kerap menyalurkan sedikit lebih dari pesanan.
  testWidgets('bacaan melebihi pesanan berhenti di penuh', (tester) async {
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(12))),
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
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(tester.widget<BatteryGauge>(find.byType(BatteryGauge)).fill, 1.0);
  });
}
