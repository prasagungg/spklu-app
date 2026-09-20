import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/connector_sheet.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub(this.statusOf);

  /// Status per nomor konektor.
  final Map<String, int> statusOf;
  int statusCalls = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path != '/status-konektor') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          data: listResponse(),
          statusCode: 200,
        ),
      );
      return;
    }

    statusCalls++;
    final id = (options.data as Map)['connectorId'] as String;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: connectorStatusResponse(
          status: statusOf[id] ?? 1,
          connectorId: id,
        ),
        statusCode: 200,
      ),
    );
  }
}

/// Charge box dua konektor yang di daftar sama-sama berstatus 1.
final _box = ChargeBox.fromJson(
  chargeBoxJson(
    connectors: [
      connectorJson(id: '1'),
      connectorJson(id: '2', nama: 'Gun 2'),
    ],
  ),
  number: 1,
);

Future<_Stub> _openSheet(
  WidgetTester tester, {
  Map<String, int> statusOf = const {},
}) async {
  final stub = _Stub(statusOf);
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showConnectorSheet(context, _box),
            child: const Text('buka'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();

  return stub;
}

void main() {
  testWidgets('status ditanyakan sekali per konektor saat sheet dibuka',
      (tester) async {
    final stub = await _openSheet(tester);

    expect(stub.statusCalls, 2);
  });

  /// Daftar charge box melaporkan 1 untuk kedua konektor; yang benar
  /// datang dari `POST /status-konektor`.
  testWidgets('status dari daftar ditimpa status hasil pemeriksaan',
      (tester) async {
    await _openSheet(tester, statusOf: {'1': 3, '2': 1});

    expect(find.text('Sedang Digunakan'), findsOneWidget);
    expect(find.text('Tersedia'), findsOneWidget);
  });

  for (final (status, label) in [
    (1, 'Tersedia'),
    (2, 'Menunggu Konektor'),
    (3, 'Sedang Digunakan'),
    (4, 'Selesai'),
  ]) {
    testWidgets('status $status berlabel "$label"', (tester) async {
      await _openSheet(tester, statusOf: {'1': status, '2': status});

      expect(find.text(label), findsNWidgets(2));
    });
  }

  testWidgets('tidak ada polling setelah pemeriksaan pertama',
      (tester) async {
    final stub = await _openSheet(tester);
    final afterOpen = stub.statusCalls;

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    expect(stub.statusCalls, afterOpen);
  });
}
