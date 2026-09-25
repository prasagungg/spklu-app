import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/card_reader_scope.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/billing.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/models/order.dart';
import 'package:kossotrik/pages/card_payment_page.dart';
import 'package:kossotrik/pages/payment_success_page.dart';
import 'package:kossotrik/services/card_reader.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/session_widgets.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';

ChargingSession _session() {
  final box = DemoData.chargeBoxes[3];

  return ChargingSession.fromOrder(
    chargeBox: box,
    connector: box.connectors.first,
    order: const Order(
      orderId: 'ORDER-1',
      sessionCode: '29',
      partnerReference: '81067',
      kwh: 19.5,
      rpTotal: 50000,
    ),
    now: DateTime(2026, 9, 16, 18, 40, 39),
  );
}

/// Halaman dengan hitung mundur dan spinner memakai timer berulang,
/// sehingga pumpAndSettle tidak akan pernah selesai.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> pumpPayment(WidgetTester tester, FakeCardReader reader) async {
  await tester.pumpWidget(
    CardReaderScope(
      reader: reader,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: CardPaymentPage(session: _session()),
      ),
    ),
  );
  await settle(tester);
}

/// Menjawab inquiry billing; bisa dibuat menolak dengan kode tertentu.
class _Billing extends Interceptor {
  _Billing({this.errorCode, this.errorPath, this.totalAmount = 25400});

  final String? errorCode;

  /// Hanya path ini yang ditolak; null berarti semuanya.
  final String? errorPath;

  final num totalAmount;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (errorCode != null && (errorPath == null || options.path == errorPath)) {
      handler.reject(
        DioException.badResponse(
          statusCode: 400,
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 400,
            data: {
              'responseCode': errorCode,
              'responseMessage': 'Ditolak backend',
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
        data: switch (options.path) {
          '/transaction/inquiry-billing' => inquiryBillingResponse(
            totalAmount: totalAmount,
          ),
          '/transaction/payment-billing' => paymentBillingResponse(
            totalAmount: totalAmount,
          ),
          _ => okResponse,
        },
      ),
    );
  }
}

/// Halaman pembayaran yang tersambung backend tiruan.
Future<void> _pumpOnline(
  WidgetTester tester,
  FakeCardReader reader,
  _Billing billing,
) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(billing)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: CardReaderScope(
        reader: reader,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: CardPaymentPage(session: _session()),
        ),
      ),
    ),
  );
  await settle(tester);
}

/// Inquiry menambah satu hop async sebelum halaman pindah.
Future<void> settleNetwork(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  _resumedSessionTests();

  _countdownTests();

  group('inquiry billing', () {
    testWidgets('tap kartu menanyakan tagihan ordernya', (tester) async {
      final reader = FakeCardReader();
      final billing = _Billing();
      await _pumpOnline(tester, reader, billing);

      reader.tap();
      await settleNetwork(tester);

      final call = billing.requests.firstWhere(
        (r) => r.path == '/transaction/inquiry-billing',
      );
      expect(call.method, 'POST');
      expect(call.data, {
        'orderId': 'ORDER-1',
        // Nomor kartu masih tetap: NFC tidak bisa membacanya.
        'cardNumber': Env.cardNumber,
      });
      expect(find.byType(PaymentSuccessPage), findsOneWidget);
    });

    /// Nominalnya harus persis dari inquiry: total order pun ditolak
    /// backend sebagai "Amount mismatch".
    testWidgets('pembayaran memakai totalAmount dari inquiry', (tester) async {
      final reader = FakeCardReader();
      final billing = _Billing(totalAmount: 145670);
      await _pumpOnline(tester, reader, billing);

      reader.tap();
      await settleNetwork(tester);

      final call = billing.requests.firstWhere(
        (r) => r.path == '/transaction/payment-billing',
      );
      expect(call.data, {
        'orderId': 'ORDER-1',
        'amount': 145670,
        'cardNumber': Env.cardNumber,
        // Wajib; tanpa itu backend membalas "Missing Field: bankLog".
        'bankLog': Env.bankLog,
        // Mesin mana yang menagih. Nilainya masih sementara, tetapi
        // fieldnya tetap harus ikut terkirim.
        'merchantId': Env.merchantId,
        'terminalId': Env.terminalId,
      });
      expect(find.byType(PaymentSuccessPage), findsOneWidget);
    });

    /// Tagihan sungguhan kerap pecahan. Dibulatkan lebih dulu,
    /// nominalnya berselisih dari inquiry dan backend membalas
    /// "Amount mismatch" (25) — pembayaran tidak pernah bisa selesai.
    testWidgets('nominal pecahan dikirim persis, tanpa dibulatkan', (
      tester,
    ) async {
      final reader = FakeCardReader();
      final billing = _Billing(totalAmount: 25161.156);
      await _pumpOnline(tester, reader, billing);

      reader.tap();
      await settleNetwork(tester);

      final call = billing.requests.firstWhere(
        (r) => r.path == '/transaction/payment-billing',
      );
      expect((call.data as Map)['amount'], 25161.156);
      expect(find.byType(PaymentSuccessPage), findsOneWidget);
      // Ditampilkan apa adanya juga — bukan dibulatkan jadi "Rp25.161".
      expect(find.text('Rp25.161,156'), findsOneWidget);
    });

    /// Konektor yang tarifnya belum diatur dihargai nol sampai ke
    /// inquiry. Mengirimkannya sebagai `amount` dibalas "Missing Field:
    /// amount" — pesan yang menyesatkan.
    testWidgets('tagihan nol dijelaskan, bukan dikirim ke pembayaran', (
      tester,
    ) async {
      final reader = FakeCardReader();
      final billing = _Billing(totalAmount: 0);
      await _pumpOnline(tester, reader, billing);

      reader.tap();
      await settleNetwork(tester);

      expect(
        billing.requests.map((r) => r.path),
        isNot(contains('/transaction/payment-billing')),
      );
      expect(find.byType(PaymentSuccessPage), findsNothing);
      expect(
        find.textContaining('tarif konektor ini belum diatur'),
        findsOneWidget,
      );
    });

    /// Kartu yang mengungkapkan nomornya dipakai apa adanya; yang
    /// tidak — MIFARE Classic seperti e-Money — jatuh ke nomor dari
    /// konfigurasi.
    testWidgets('nomor dari kartu dipakai bila kartunya membukanya', (
      tester,
    ) async {
      final reader = FakeCardReader();
      final billing = _Billing();
      await _pumpOnline(tester, reader, billing);

      reader.tap(cardNumber: '6019213456789012');
      await settleNetwork(tester);

      for (final path in [
        '/transaction/inquiry-billing',
        '/transaction/payment-billing',
      ]) {
        final call = billing.requests.firstWhere((r) => r.path == path);
        expect(
          (call.data as Map)['cardNumber'],
          '6019213456789012',
          reason: path,
        );
      }
    });

    testWidgets('kartu tanpa nomor jatuh ke nomor konfigurasi', (tester) async {
      final reader = FakeCardReader();
      final billing = _Billing();
      await _pumpOnline(tester, reader, billing);

      reader.tap();
      await settleNetwork(tester);

      final call = billing.requests.firstWhere(
        (r) => r.path == '/transaction/inquiry-billing',
      );
      expect((call.data as Map)['cardNumber'], Env.cardNumber);
    });

    testWidgets('tagihan ditanyakan lebih dulu, baru dibayar', (tester) async {
      final reader = FakeCardReader();
      final billing = _Billing();
      await _pumpOnline(tester, reader, billing);

      reader.tap();
      await settleNetwork(tester);

      final paths = billing.requests
          .map((r) => r.path)
          .where((p) => p.startsWith('/transaction/'))
          .toList();
      expect(paths, [
        '/transaction/inquiry-billing',
        '/transaction/payment-billing',
      ]);
    });

    testWidgets('nominal yang ditolak menahan alur', (tester) async {
      final reader = FakeCardReader();
      await _pumpOnline(
        tester,
        reader,
        _Billing(errorCode: '25', errorPath: '/transaction/payment-billing'),
      );

      reader.tap();
      await settleNetwork(tester);

      expect(find.byType(PaymentSuccessPage), findsNothing);
      expect(
        find.textContaining('Nominal tagihan tidak cocok'),
        findsOneWidget,
      );
    });

    testWidgets('pembayaran gagal tidak menghitungnya sebagai dibayar', (
      tester,
    ) async {
      final reader = FakeCardReader();
      await _pumpOnline(
        tester,
        reader,
        _Billing(errorCode: '24', errorPath: '/transaction/payment-billing'),
      );

      reader.tap();
      await settleNetwork(tester);

      expect(find.textContaining('Transaksi ditolak'), findsOneWidget);
      // Kartu bisa ditempelkan lagi.
      expect(reader.isWaiting, isTrue);
    });

    /// Maju ke "Pembayaran Berhasil" untuk tagihan yang tidak pernah
    /// terverifikasi jauh lebih berbahaya daripada menahan pengguna.
    testWidgets('kartu yang tidak didukung menahan alur', (tester) async {
      final reader = FakeCardReader();
      await _pumpOnline(tester, reader, _Billing(errorCode: '05'));

      reader.tap();
      await settleNetwork(tester);

      expect(find.byType(PaymentSuccessPage), findsNothing);
      expect(find.textContaining('Kartu ini tidak didukung'), findsOneWidget);
    });

    testWidgets('order kedaluwarsa dijelaskan', (tester) async {
      final reader = FakeCardReader();
      await _pumpOnline(tester, reader, _Billing(errorCode: '21'));

      reader.tap();
      await settleNetwork(tester);

      expect(
        find.textContaining('Pesanan tidak ditemukan atau sudah kedaluwarsa'),
        findsOneWidget,
      );
    });

    testWidgets('gagal menagih membuka lagi pembacaan kartu', (tester) async {
      final reader = FakeCardReader();
      await _pumpOnline(tester, reader, _Billing(errorCode: '05'));

      reader.tap();
      await settleNetwork(tester);

      // Sesi NFC dibuka kembali supaya kartu bisa ditempelkan ulang.
      expect(reader.isWaiting, isTrue);
    });
  });

  group('penerbit kartu', () {
    test('prefix menentukan penerbitnya', () {
      expect(issuerOf('0123456789012345'), 'EM-BNI');
      expect(issuerOf('4567000000000000'), 'EM-BRI');
      expect(issuerOf('8901000000000000'), 'EM-BCA');
      expect(issuerOf('2345000000000000'), 'EM-MANDIRI');
    });

    test('prefix tak dikenal tidak punya penerbit', () {
      expect(issuerOf('9999000000000000'), isNull);
      expect(issuerOf('012'), isNull);
    });

    test('nomor bawaan memakai prefix yang didukung', () {
      expect(issuerOf(Env.cardNumber), isNotNull);
    });
  });

  testWidgets('tidak ada lagi tombol bayar', (tester) async {
    await pumpPayment(tester, FakeCardReader());

    expect(find.text('Bayar (Simulasi)'), findsNothing);
    expect(find.text('Menunggu Kartu'), findsOneWidget);
  });

  testWidgets('pembaca langsung menunggu kartu saat halaman dibuka', (
    tester,
  ) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    expect(reader.isWaiting, isTrue);
  });

  testWidgets('tap kartu memajukan ke Pembayaran Berhasil', (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    reader.tap();
    await settle(tester);

    expect(find.byType(PaymentSuccessPage), findsOneWidget);
    expect(find.text('Pembayaran Berhasil'), findsOneWidget);
  });

  testWidgets('sesi NFC dihentikan setelah kartu diterima', (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    reader.tap();
    await settle(tester);

    expect(reader.stopCount, greaterThan(0));
    expect(reader.isWaiting, isFalse);
  });

  /// Android melaporkan kartu yang sama berulang selama masih menempel.
  /// Tap kedua tidak boleh mendorong halaman untuk kedua kalinya.
  testWidgets('kartu yang terbaca berkali-kali hanya dihitung sekali', (
    tester,
  ) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    reader.tap();
    reader.tap();
    reader.tap();
    await settle(tester);

    // Tiga tap, satu halaman. Kalau penjaganya hilang, tiap tap
    // mendorong rute baru dan jumlahnya ikut bertambah.
    expect(find.byType(PaymentSuccessPage), findsOneWidget);
  });

  testWidgets('NFC yang dimatikan dijelaskan, bukan dibiarkan menggantung', (
    tester,
  ) async {
    await pumpPayment(
      tester,
      FakeCardReader(reportedStatus: CardReaderStatus.disabled),
    );

    expect(find.text('Menunggu Kartu'), findsNothing);
    expect(find.textContaining('NFC sedang mati'), findsOneWidget);
    expect(find.text('Periksa Lagi'), findsOneWidget);
  });

  testWidgets('perangkat tanpa NFC diberi tahu dan diarahkan ke petugas', (
    tester,
  ) async {
    await pumpPayment(
      tester,
      FakeCardReader(reportedStatus: CardReaderStatus.unsupported),
    );

    expect(find.textContaining('tidak punya pembaca NFC'), findsOneWidget);
    expect(find.text('Menunggu Kartu'), findsNothing);
  });

  testWidgets('Periksa Lagi memeriksa ulang kesiapan pembaca', (tester) async {
    final reader = FakeCardReader(reportedStatus: CardReaderStatus.disabled);
    await pumpPayment(tester, reader);

    await tester.tap(find.text('Periksa Lagi'));
    await settle(tester);

    // Masih mati, jadi keterangannya tetap dan halaman tidak berpindah.
    expect(find.textContaining('NFC sedang mati'), findsOneWidget);
    expect(find.byType(PaymentSuccessPage), findsNothing);
  });

  testWidgets('sesi NFC ditutup saat halaman ditinggalkan', (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(reader.stopCount, greaterThan(0));
  });
}

void _countdownTests() {
  testWidgets('hitung mundur dibaca dari sessionExpiredTime order', (
    tester,
  ) async {
    final expiry = DateTime.now().add(const Duration(minutes: 9, seconds: 33));
    final box = DemoData.chargeBoxes[3];
    final session = ChargingSession.fromOrder(
      chargeBox: box,
      connector: box.connectors.first,
      order: Order(
        orderId: 'ORDER-1',
        sessionCode: '29',
        partnerReference: '81067',
        kwh: 19.5,
        rpTotal: 50000,
        sessionExpiredAt: expiry,
      ),
      now: DateTime(2026, 9, 16, 18, 40, 39),
    );

    await tester.pumpWidget(
      CardReaderScope(
        reader: FakeCardReader(),
        child: MaterialApp(
          theme: AppTheme.build(),
          home: CardPaymentPage(session: session),
        ),
      ),
    );
    await settle(tester);

    final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
    // Batas waktu order, bukan 10 menit tetap milik aplikasi.
    expect(pill.remaining.inSeconds, closeTo(573, 2));
  });

  testWidgets('tanpa batas waktu order, hitung mundur jatuh ke 10 menit', (
    tester,
  ) async {
    await pumpPayment(tester, FakeCardReader());

    final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
    expect(pill.remaining, const Duration(minutes: 10));
  });
}

void _resumedSessionTests() {
  /// Sesi yang dilanjutkan dari daftar masuk langsung ke halaman
  /// pembayaran, tanpa membawa rincian order. Halaman "Pembayaran
  /// Berhasil" sempat memaksa rincian itu ada dan jatuh dengan
  /// "Null check operator used on a null value".
  testWidgets('sesi lanjutan tanpa rincian order tetap bisa dibayar', (
    tester,
  ) async {
    final box = DemoData.chargeBoxes[3];
    final reader = FakeCardReader();
    final billing = _Billing(totalAmount: 25161.14);
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(billing)),
    );

    await tester.pumpWidget(
      ChargingScope(
        repository: repo,
        child: CardReaderScope(
          reader: reader,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: CardPaymentPage(
              session: ChargingSession.resumed(
                chargeBox: box,
                connector: box.connectors.first,
                now: DateTime(2026, 9, 25),
                orderId: 'ORDER-1',
                sessionCode: '70',
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    reader.tap();
    await settleNetwork(tester);

    expect(find.byType(PaymentSuccessPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Yang ditampilkan angka yang benar-benar didebit.
    expect(find.text('Rp25.161,14'), findsWidgets);
  });
}
