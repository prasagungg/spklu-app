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
    if (options.path == '/detail-chargerbox') statusCalls++;

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: switch (options.path) {
          '/detail-chargerbox' => chargeBoxDetailResponse(
              connectors: [
                for (final id in ['1', '2'])
                  connectorJson(
                    id: id,
                    nama: 'Gun $id',
                    status: statusOf[id] ?? 1,
                  ),
              ],
            ),
          '/transaction/history-transaction' => historyResponse(const []),
          _ => listResponse(),
        },
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

/// Menjawab detail tanpa satu pun konektor.
class _EmptyDetail extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path == '/detail-chargerbox'
            ? chargeBoxDetailResponse(connectors: const [])
            : okResponse,
      ),
    );
  }
}

void main() {
  /// Satu panggilan detail memberi seluruh konektor sekaligus —
  /// sebelumnya satu panggilan per konektor.
  testWidgets('isi charge box diambil sekali saat sheet dibuka',
      (tester) async {
    final stub = await _openSheet(tester);

    expect(stub.statusCalls, 1);
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

  testWidgets('tiap konektor punya jalan ke riwayat transaksinya',
      (tester) async {
    await _openSheet(tester);

    // Satu tombol per konektor — endpoint riwayat memang per konektor.
    for (final id in [1, 2]) {
      expect(
        find.byKey(Key('riwayat-konektor-$id')),
        findsOneWidget,
        reason: 'konektor $id',
      );
    }

    await tester.tap(find.byKey(const Key('riwayat-konektor-2')));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat Transaksi'), findsOneWidget);
    // Subjudulnya menyebut konektor yang dibuka, bukan yang pertama.
    expect(find.textContaining('Gun 2'), findsOneWidget);
  });

  /// Sheet yang dikosongkan oleh jawaban aneh jauh lebih buruk
  /// daripada sheet yang menampilkan data daftar apa adanya.
  testWidgets('detail tanpa konektor tidak mengosongkan sheet',
      (tester) async {
    await tester.pumpWidget(
      ChargingScope(
        repository: ChargePointRepository(
          client: ApiClient.withDio(
            Dio()..interceptors.add(_EmptyDetail()),
          ),
        ),
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

    expect(find.text('Gun 1'), findsOneWidget);
    expect(find.text('Gun 2'), findsOneWidget);
  });

  testWidgets('tidak ada polling setelah pemeriksaan pertama',
      (tester) async {
    final stub = await _openSheet(tester);
    final afterOpen = stub.statusCalls;

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    expect(stub.statusCalls, afterOpen);
  });
}
