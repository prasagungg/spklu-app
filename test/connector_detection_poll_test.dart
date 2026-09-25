import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/connect_connector_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/primary_button.dart';
import 'package:kossotrik/widgets/session_widgets.dart';

import 'fixtures.dart';

/// Melaporkan status OCPP yang bisa diubah test di tengah jalan.
class _Stub extends Interceptor {
  _Stub(this.status);

  String status;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path == '/check-status-connector'
            ? connectorStatusResponse(status: status)
            : okResponse,
      ),
    );
  }

  List<RequestOptions> get checks =>
      requests.where((r) => r.path == '/check-status-connector').toList();
}

ChargingSession _session() {
  final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

  return ChargingSession(
    chargeBox: box,
    connector: box.connectors.single,
    sessionCode: '29',
    reference: '81067',
    createdAt: DateTime(2026),
    orderId: 'ORDER-1',
  );
}

Future<_Stub> _pump(WidgetTester tester, {String status = 'Available'}) async {
  final stub = _Stub(status);
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: ConnectConnectorPage(session: _session()),
      ),
    ),
  );
  await tester.pump();

  return stub;
}

PrimaryButton _startButton(WidgetTester tester) => tester.widget<PrimaryButton>(
  find.widgetWithText(PrimaryButton, 'Mulai Pengisian'),
);

/// Satu putaran polling.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('status konektor ditanyakan tiap detik', (tester) async {
    final stub = await _pump(tester);

    await _tick(tester);
    await _tick(tester);

    expect(stub.checks, hasLength(greaterThanOrEqualTo(2)));
    expect(stub.checks.first.data, {
      'chargeBoxId': 'CB-SMR-01',
      'connectorId': '1',
    });
  });

  /// Selama charger masih melaporkan "Available", kabelnya belum
  /// terpasang dan perintah start tidak boleh bisa dikirim.
  testWidgets('tombol mati selama konektor masih Available', (tester) async {
    await _pump(tester);

    for (var i = 0; i < 5; i++) {
      await _tick(tester);
    }

    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(find.text('Menunggu konektor terdeteksi...'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
  });

  testWidgets('Preparing berarti nozzle sudah tercolok', (tester) async {
    final stub = await _pump(tester);

    await _tick(tester);
    expect(_startButton(tester).onPressed, isNull);

    // Kabel dicolokkan ke kendaraan.
    stub.status = 'Preparing';
    await _tick(tester);

    expect(find.text('Konektor Terhubung'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNotNull);
  });

  testWidgets('pemeriksaan berhenti setelah konektor terdeteksi', (
    tester,
  ) async {
    final stub = await _pump(tester, status: 'Preparing');

    await _tick(tester);
    final afterDetection = stub.checks.length;

    await _tick(tester);
    await _tick(tester);

    expect(stub.checks, hasLength(afterDetection));
  });

  /// Menebak status yang tidak dikenal sebagai "tercolok" akan
  /// mengirim perintah start yang pasti ditolak charger.
  testWidgets('status tak dikenal tidak dianggap tercolok', (tester) async {
    final stub = await _pump(tester);
    stub.status = 'SomethingElse';

    await _tick(tester);
    await _tick(tester);

    expect(tester.takeException(), isNull);
    expect(_startButton(tester).onPressed, isNull);
  });

  /// Charger bisa melewati "Preparing" bila sesinya sudah jalan; kalau
  /// keadaan sesudahnya tidak ikut dihitung, halamannya menggantung.
  testWidgets('status sesudah Preparing juga berarti kabelnya terpasang', (
    tester,
  ) async {
    await _pump(tester, status: 'SuspendedEV');

    await _tick(tester);

    expect(_startButton(tester).onPressed, isNotNull);
  });

  /// Charger yang rusak tidak akan pernah melaporkan "Preparing".
  /// Menyuruh pengguna menunggu di situ hanya membuang waktunya.
  testWidgets('konektor bermasalah dikatakan apa adanya', (tester) async {
    await _pump(tester, status: 'Faulted');

    await _tick(tester);

    expect(find.textContaining('tidak bisa dipakai (Faulted)'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
  });

  testWidgets('hitung mundur dibaca dari sessionExpired tagihan', (
    tester,
  ) async {
    final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);
    final expiry = DateTime.now().add(const Duration(minutes: 8, seconds: 31));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ConnectConnectorPage(
          session: ChargingSession(
            chargeBox: box,
            connector: box.connectors.single,
            sessionCode: '29',
            reference: '81067',
            createdAt: DateTime(2026),
            orderId: 'ORDER-1',
            // Tenggat yang dikirim payment-billing, bukan sepuluh menit
            // tetap milik aplikasi.
            expiresAt: expiry,
          ),
        ),
      ),
    );
    await tester.pump();

    final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
    expect(pill.remaining.inSeconds, closeTo(511, 2));
  });
}
