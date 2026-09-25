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
  _Stub({this.body, this.detail, this.fail = false});

  final Map<String, dynamic>? body;

  /// Jawaban `detail-history-transaction` menurut kode sesi yang
  /// diketik.
  final Map<String, dynamic>? Function(String sessionCode)? detail;

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

    if (options.path == '/transaction/detail-history-transaction') {
      final code = (options.data as Map)['sessionCode'] as String;
      final answer = detail?.call(code);

      if (answer == null) {
        handler.reject(
          DioException.badResponse(
            statusCode: 404,
            requestOptions: options,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 404,
              // Kegagalannya tetap camelCase, tidak seperti amplop
              // suksesnya.
              data: {
                'responseCode': '21',
                'responseMessage': 'Transaction Not Found',
              },
            ),
          ),
        );
        return;
      }

      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: answer,
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

/// Charge box dengan dua konektor, untuk menguji pencocokan entri ke
/// konektornya.
final _twoConnectors = ChargeBox.fromJson(
  chargeBoxJson(
    connectors: [
      connectorJson(id: '1'),
      connectorJson(id: '2', nama: 'Gun 2'),
    ],
  ),
  number: 4,
);

Future<_Stub> _pump(
  WidgetTester tester, {
  _Stub? stub,
  List<ChargeBox>? chargeBoxes,
}) async {
  final it = stub ?? _Stub();
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(it)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: TransactionHistoryPage(chargeBoxes: chargeBoxes ?? [_box]),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return it;
}

/// Mengetik kode sesi pada keypad lalu menekan "Lihat Rincian".
Future<void> _enterCode(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    await tester.tap(find.widgetWithText(InkWell, digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('Lihat Rincian'));
  await tester.pumpAndSettle();
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

    /// Endpoint-nya melayani seluruh riwayat sekali panggil, jadi asal
    /// tiap entri tidak bisa lagi diambil dari permintaannya.
    test('entri menyebut charge box dan konektornya sendiri', () {
      final entry = TransactionHistoryEntry.fromJson(historyEntryJson());

      expect(entry.chargeBoxId, 'CB-SMR-01');
      expect(entry.chargeBoxName, 'Kempower Satellite 200 kW');
      expect(entry.connectorId, 1);
      expect(entry.connectorName, 'Gun 1');
    });

    /// Ejaan b besar/kecil berbeda antar endpoint, dan `connectorId`
    /// dikirim sebagai angka di sebagian di antaranya.
    test('kedua ejaan asal entri diterima', () {
      final entry = TransactionHistoryEntry.fromJson(const {
        'orderId': 'X',
        'chargeBoxId': 'ACMP_UAT',
        'chargeBoxName': 'ACMP UAT',
        'connectorId': 2,
        'connectorName': 'AC 22 kW',
      });

      expect(entry.chargeBoxId, 'ACMP_UAT');
      expect(entry.chargeBoxName, 'ACMP UAT');
      expect(entry.connectorId, 2);
      expect(entry.connectorName, 'AC 22 kW');
    });

    test('entri tanpa asal tidak memunculkan error', () {
      final entry = TransactionHistoryEntry.fromJson(const {'orderId': 'X'});

      expect(entry.chargeBoxId, isEmpty);
      expect(entry.connectorId, isNull);
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
    /// Endpoint-nya kini GET tanpa body: seluruh riwayat datang dalam
    /// satu jawaban, jadi tidak ada lagi panggilan per konektor.
    testWidgets('riwayat diminta sekali, GET tanpa body', (tester) async {
      final stub = await _pump(tester, chargeBoxes: [_twoConnectors]);

      final call = stub.requests.single;
      expect(call.method, 'GET');
      expect(call.path, '/transaction/history-transaction');
      expect(call.data, isNull);
    });

    /// Entri menyebut charge box dan konektornya sendiri; daftar lokasi
    /// hanya melengkapi nomor urut, daya, dan tipe konektornya.
    testWidgets('entri dicocokkan ke konektor asalnya', (tester) async {
      await _pump(
        tester,
        chargeBoxes: [_twoConnectors],
        stub: _Stub(
          body: historyResponse([
            historyEntryJson(totalAmount: 11000),
            historyEntryJson(
              orderId: '5SZJ9T6XLDUVP26LNPN89PDNA4',
              totalAmount: 22000,
              connectorId: '2',
              connectorName: 'Gun 2',
            ),
          ]),
        ),
      );

      expect(find.byType(TransactionHistoryCard), findsNWidgets(2));
      expect(find.text('Gun 1 - CCS2 - 200 kW DC'), findsOneWidget);
      expect(find.text('Gun 2 - CCS2 - 200 kW DC'), findsOneWidget);
    });

    /// Riwayat seluruh lokasi tidak ada gunanya kalau urutannya acak.
    testWidgets('transaksi terbaru muncul lebih dulu', (tester) async {
      await _pump(
        tester,
        chargeBoxes: [_twoConnectors],
        stub: _Stub(
          body: historyResponse([
            historyEntryJson(
              totalAmount: 11000,
              createdDate: '2026-09-20T08:00:00Z',
            ),
            historyEntryJson(
              orderId: '5SZJ9T6XLDUVP26LNPN89PDNA4',
              totalAmount: 22000,
              createdDate: '2026-09-23T08:00:00Z',
              connectorId: '2',
              connectorName: 'Gun 2',
            ),
          ]),
        ),
      );

      final cards = find.byType(TransactionHistoryCard);
      expect(
        tester.getCenter(find.text('Rp22.000')).dy,
        lessThan(tester.getCenter(find.text('Rp11.000')).dy),
      );
      expect(cards, findsNWidgets(2));
    });

    testWidgets('tiap transaksi tampil sesuai desain', (tester) async {
      await _pump(tester);

      expect(find.byType(TransactionHistoryCard), findsNWidgets(2));
      // Judul memakai nomor dan nama charge box.
      expect(find.text('04 - Kempower Satellite 200 kW'), findsNWidgets(2));
      // Nama konektor, tipenya, lalu daya charge box — seperti desain.
      expect(find.text('Gun 1 - CCS2 - 200 kW DC'), findsNWidgets(2));
      expect(find.text('Rp12.700'), findsOneWidget);
      expect(find.text('Rp50.000'), findsOneWidget);
      expect(find.text('6012 **** **** 7890'), findsNWidgets(2));
    });

    /// Pencarian di desainnya menyebut tanggal, charger, dan nominal;
    /// ketiganya disaring di aplikasi karena endpoint riwayat tidak
    /// menerima kata kunci apa pun.
    testWidgets('pencarian menyaring daftar', (tester) async {
      await _pump(
        tester,
        stub: _Stub(
          body: historyResponse([
            historyEntryJson(totalAmount: 12700),
            historyEntryJson(
              totalAmount: 50000,
              createdDate: '2026-08-01T10:00:00Z',
            ),
          ]),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Agu');
      await tester.pumpAndSettle();

      expect(find.text('Rp50.000'), findsOneWidget);
      expect(find.text('Rp12.700'), findsNothing);

      // Kotak pencariannya tetap ada supaya kata kuncinya bisa dihapus.
      expect(find.byType(TextField), findsOneWidget);
    });

    /// Daftar boleh dilihat siapa saja; rinciannya milik pemegang kode.
    testWidgets('kartu ditekan meminta kode sesi lalu membuka rincian', (
      tester,
    ) async {
      await _pump(
        tester,
        stub: _Stub(
          body: historyResponse([historyEntryJson()]),
          detail: (code) => code == '29' ? transactionDetailResponse() : null,
        ),
      );

      await tester.tap(find.byType(TransactionHistoryCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Kode Sesi'), findsOneWidget);

      // Kode yang salah ditolak backend, dan alurnya berhenti di sini.
      await _enterCode(tester, '11');
      expect(
        find.text('Kode sesi tidak cocok dengan transaksi ini'),
        findsOneWidget,
      );
      expect(find.text('Detail Transaksi'), findsNothing);

      await _enterCode(tester, '29');

      expect(find.text('Detail Transaksi'), findsOneWidget);
      // Angka-angkanya dari backend, termasuk nomor kartu yang sudah
      // disamarkan di sana.
      expect(find.text('6,4 kWh'), findsOneWidget);
      expect(find.text('Rp50.000'), findsOneWidget);
      expect(find.text('Rp32.500'), findsOneWidget);
      expect(find.text('601••••••••••890'), findsOneWidget);
    });

    /// Riwayat kini mencakup charge box yang tidak sedang ditampilkan
    /// daftar. Menyembunyikannya berarti transaksinya hilang dari mata
    /// pengguna, jadi barisnya tetap ada memakai nama dari entrinya —
    /// tanpa nomor urut, yang hanya dimiliki daftar.
    testWidgets('riwayat charge box di luar daftar tetap tampil', (
      tester,
    ) async {
      await _pump(
        tester,
        stub: _Stub(
          body: historyResponse([
            historyEntryJson(
              chargeBoxId: 'delta_sensi',
              chargeBoxName: 'Delta DC Wallbox',
              connectorId: '1',
              connectorName: 'AC TYPE 2',
            ),
          ]),
        ),
      );

      expect(find.text('Delta DC Wallbox'), findsOneWidget);
      expect(find.textContaining('04 -'), findsNothing);
      expect(find.text('Rp12.700'), findsOneWidget);
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
