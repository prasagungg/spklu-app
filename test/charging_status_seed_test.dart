import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/charging_status_page.dart';
import 'package:kossotrik/theme/app_theme.dart';

ChargeBox _box({Map<String, dynamic>? session}) => ChargeBox.fromJson({
      'id': 'SIM-456',
      'connectors': [
        {
          'id': 1,
          'status': session == null ? 'Available' : 'Charging',
          'errorCode': 'NoError',
          'session': session,
        },
      ],
    }, number: 1);

Future<void> _pump(WidgetTester tester, ChargeBox box) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      // Tanpa ChargingScope halaman tidak memanggil /progress, jadi yang
      // tampil murni nilai awal.
      home: ChargingStatusPage(
        session: ChargingSession.resumed(
          chargeBox: box,
          connector: box.connectors.single,
          now: DateTime(2026),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('energi awal diambil dari sesi yang dibawa /list',
      (tester) async {
    await _pump(
      tester,
      _box(session: const {
        'chargePointId': 'SIM-456',
        'connectorId': 1,
        'transactionId': 42,
        'state': 'charging',
        'energyWh': 127,
        'powerW': 12000,
        'percent': 55.5,
        'durationSeconds': 41,
      }),
    );

    // Langsung menampilkan angka sesungguhnya, bukan 0.
    expect(find.text('0,127 kWh'), findsOneWidget);
    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  testWidgets('tanpa sesi berjalan, mulai dari nol', (tester) async {
    await _pump(tester, _box());

    expect(find.text('0,000 kWh'), findsOneWidget);
  });
}
