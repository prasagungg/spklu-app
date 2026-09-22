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

import 'fixtures.dart';

/// Melaporkan tahap proses yang bisa diubah test di tengah jalan.
class _Stub extends Interceptor {
  _Stub(this.statusProcess);

  int statusProcess;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path == '/manage-sessioncode'
            ? sessionCodeResponse(statusProcess: statusProcess)
            : okResponse,
      ),
    );
  }

  List<RequestOptions> get checks =>
      requests.where((r) => r.path == '/manage-sessioncode').toList();
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

Future<_Stub> _pump(WidgetTester tester, {int statusProcess = 2}) async {
  final stub = _Stub(statusProcess);
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
  testWidgets('tahap proses ditanyakan tiap detik', (tester) async {
    final stub = await _pump(tester);

    await _tick(tester);
    await _tick(tester);

    expect(stub.checks, hasLength(greaterThanOrEqualTo(2)));
    expect(stub.checks.first.data, {
      'chargeBoxId': 'CB-SMR-01',
      'connectorId': '1',
      // Kode sesi dari order yang sedang dibeli.
      'sessionCode': '29',
    });
  });

  /// Selama backend masih meminta konektor dihubungkan, perintah start
  /// tidak boleh bisa dikirim.
  testWidgets('tombol mati selama statusProcess masih 2', (tester) async {
    await _pump(tester);

    for (var i = 0; i < 5; i++) {
      await _tick(tester);
    }

    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(find.text('Menunggu konektor terdeteksi...'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
  });

  testWidgets('statusProcess naik berarti nozzle sudah tercolok',
      (tester) async {
    final stub = await _pump(tester);

    await _tick(tester);
    expect(_startButton(tester).onPressed, isNull);

    // Kabel dicolokkan ke kendaraan.
    stub.statusProcess = 3;
    await _tick(tester);

    expect(find.text('Konektor Terhubung'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNotNull);
  });

  testWidgets('pemeriksaan berhenti setelah konektor terdeteksi',
      (tester) async {
    final stub = await _pump(tester, statusProcess: 3);

    await _tick(tester);
    final afterDetection = stub.checks.length;

    await _tick(tester);
    await _tick(tester);

    expect(stub.checks, hasLength(afterDetection));
  });

  /// Menebak angka yang tidak dikenal sebagai "tercolok" akan mengirim
  /// perintah start yang pasti ditolak charger.
  testWidgets('status tak dikenal tidak dianggap tercolok', (tester) async {
    final stub = await _pump(tester);
    stub.statusProcess = 99;

    await _tick(tester);
    await _tick(tester);

    expect(tester.takeException(), isNull);
    expect(_startButton(tester).onPressed, isNull);
  });

  testWidgets('status selesai juga berarti kabelnya terpasang',
      (tester) async {
    await _pump(tester, statusProcess: 4);

    await _tick(tester);

    expect(_startButton(tester).onPressed, isNotNull);
  });
}
