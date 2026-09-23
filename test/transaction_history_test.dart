import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/data/formatters.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/transaction_history.dart';
import 'package:kossotrik/pages/transaction_history_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub({this.body, this.fail = false});

  final Map<String, dynamic>? body;
  final bool fail;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (fail) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: body ?? historyResponse(),
      ),
    );
  }
}

final _box = ChargeBox.fromJson(chargeBoxJson(), number: 4);

Future<_Stub> _pump(WidgetTester tester, {_Stub? stub}) async {
  final it = stub ?? _Stub();
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(it)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: TransactionHistoryPage(
          chargeBox: _box,
          connector: _box.connectors.single,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return it;
}

void main() {
  group('penguraian', () {
    test('entri diurai dari payload nyata', () {
      final entry = TransactionHistoryEntry.fromJson(historyEntryJson());

      expect(entry.orderId, '8XWS0G9RULEYBLHS48ULF6OFH7');
      expect(entry.pspId, 'EM-BNI');
      expect(entry.totalAmount, 12700);
      expect(entry.createdAt, isNotNull);
      expect(entry.isPaid, isTrue);
    });

    /// Backend mengirim nomor kartu utuh; desain hanya menampilkan
    /// empat digit depan dan belakang.
    test('nomor kartu disamarkan seperti desain', () {
      expect(
        TransactionHistoryEntry.fromJson(
          historyEntryJson(cardNumber: '6012345678907890'),
        ).maskedCard,
        '6012 **** **** 7890',
      );
    });

    test('transaksi yang tidak pernah dibayar tidak punya kartu', () {
      final entry = TransactionHistoryEntry.fromJson(
        historyEntryJson(pspId: '', cardNumber: ''),
      );

      expect(entry.isPaid, isFalse);
      expect(entry.maskedCard, '-');
    });

    test('nomor pendek tidak dipaksa disamarkan', () {
      expect(
        TransactionHistoryEntry.fromJson(
          historyEntryJson(cardNumber: '1234'),
        ).maskedCard,
        '1234',
      );
    });
  });

  group('tanggal', () {
    test('ditampilkan gaya Indonesia', () {
      expect(
        formatDateTime(DateTime(2026, 9, 21, 16, 42)),
        '21 Sep 2026, 16:42',
      );
    });

    test('menit satu digit diberi nol di depan', () {
      expect(formatDateTime(DateTime(2026, 1, 2, 3, 4)), '2 Jan 2026, 03:04');
    });

    test('tanpa tanggal menghasilkan tanda hubung', () {
      expect(formatDateTime(null), '-');
    });
  });

  group('halaman', () {
    testWidgets('riwayat diminta untuk konektor yang dibuka', (tester) async {
      final stub = await _pump(tester);

      final call = stub.requests.single;
      expect(call.method, 'POST');
      expect(call.path, '/transaction/history-transaction');
      expect(call.data, {'chargeBoxId': 'CB-SMR-01', 'connectorId': '1'});
    });

    testWidgets('tiap transaksi tampil sesuai desain', (tester) async {
      await _pump(tester);

      expect(find.byType(TransactionHistoryCard), findsNWidgets(2));
      // Judul memakai nomor dan nama charge box.
      expect(
        find.text('04 - Kempower Satellite 200 kW'),
        findsNWidgets(2),
      );
      // Tipe konektor dengan daya charge box, seperti desain.
      expect(find.text('CCS2 - 200 kW DC'), findsNWidgets(2));
      expect(find.text('Rp12.700'), findsOneWidget);
      expect(find.text('Rp50.000'), findsOneWidget);
      expect(find.text('6012 **** **** 7890'), findsNWidgets(2));
    });

    testWidgets('riwayat kosong dijelaskan', (tester) async {
      await _pump(tester, stub: _Stub(body: historyResponse(const [])));

      expect(find.text('Belum ada transaksi'), findsOneWidget);
    });

    testWidgets('kegagalan bisa dicoba lagi', (tester) async {
      await _pump(tester, stub: _Stub(fail: true));

      expect(find.text('Gagal memuat riwayat'), findsOneWidget);
      expect(find.text('Coba Lagi'), findsOneWidget);
    });
  });
}
