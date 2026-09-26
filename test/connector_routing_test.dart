import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

import 'package:kossotrik/widgets/session_widgets.dart';

import 'fixtures.dart';
import 'flow_helpers.dart';

class _Stub extends Interceptor {
  _Stub(
    this.status, {
    this.statusProcess = 3,
    this.orderReadable = true,
    this.sessionExpiredTime,
    this.detailExpiredTime,
  });

  /// Status konektor pada `detail-chargerbox` — menentukan bisa
  /// ditekan atau tidak, dan perlu verifikasi kode sesi atau tidak.
  final int status;

  /// Tahap transaksi pada `manage-sessioncode` — menentukan halaman
  /// tempat sesi yang sudah berjalan dilanjutkan.
  final int statusProcess;

  /// Rincian order bisa dibaca lewat `charging/detail`. Dimatikan untuk
  /// menguji jalan mundurnya.
  final bool orderReadable;

  /// Tenggat sesi pada jawaban `manage-sessioncode`.
  final String? sessionExpiredTime;

  /// Tenggat yang dijawab `charging/detail`.
  final String? detailExpiredTime;

  final List<RequestOptions> requests = [];

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.path == path).toList();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/transaction/charging/ongoing-kwh' => ongoingKwhResponse(status: 3),
          '/transaction/charging/detail' =>
            orderReadable
                ? chargingDetailResponse(sessionExpiredTime: detailExpiredTime)
                : okResponse,
          // Status sebenarnya datang dari sini, bukan dari daftar.
          '/detail-chargerbox' => chargeBoxDetailResponse(
            connectors: [connectorJson(status: status)],
          ),
          '/booked-connector' => bookingResponse(),
          '/manage-sessioncode' => sessionCodeResponse(
            statusProcess: statusProcess,
            sessionExpiredTime: sessionExpiredTime,
          ),
          // Kabelnya dianggap sudah terpasang; penungguannya
          // diuji tersendiri di connector_detection_poll_test.
          '/check-status-connector' => connectorStatusResponse(),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/transaction/payment-billing' => paymentBillingResponse(),
          '/cancelled-connector' => cancellationResponse(),
          _ => listResponse([
            chargeBoxJson(nama: 'CB-SMR-01', connectors: [connectorJson()]),
          ]),
        },
        statusCode: 200,
      ),
    );
  }
}

/// Membuka bottom sheet lalu menekan konektor satu-satunya.
Future<_Stub> _tapConnector(
  WidgetTester tester,
  int status, {
  int statusProcess = 3,
  bool orderReadable = true,
  String? sessionExpiredTime,
  String? detailExpiredTime,
}) async {
  final stub = _Stub(
    status,
    statusProcess: statusProcess,
    orderReadable: orderReadable,
    sessionExpiredTime: sessionExpiredTime,
    detailExpiredTime: detailExpiredTime,
  );
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );

  await tester.pumpWidget(SPKLUApp(repository: repo));
  await tester.pumpAndSettle();

  await tester.tap(find.text('01'));
  await tester.pumpAndSettle();
  expect(find.text('Daftar Konektor'), findsOneWidget);
  // Status diperiksa saat sheet dibuka, jadi chip "Memeriksa…" sudah
  // tergantikan di sini.
  expect(find.text('Memeriksa…'), findsNothing);

  await tester.tap(find.text('Gun 1'));
  await settleFrames(tester);

  return stub;
}

/// Konektor yang sudah diklaim menuntut kode sesi dulu; kodenya
/// diperiksa backend lewat `/manage-sessioncode`.
Future<void> _verify(WidgetTester tester) async {
  expect(find.text('Verifikasi Sesi'), findsOneWidget);
  await enterSessionCode(tester, '29');
}

void main() {
  testWidgets('status 1 membuka alur pembelian tanpa verifikasi', (
    tester,
  ) async {
    await _tapConnector(tester, 1);

    expect(find.text('Verifikasi Sesi'), findsNothing);
    // Kode sesinya ditunjukkan dulu, baru pemilihan kWh.
    await passSessionCode(tester);
    expect(find.text('Pilih kWh'), findsOneWidget);
  });

  testWidgets('konektor yang dipakai menuntut kode sesi dulu', (tester) async {
    await _tapConnector(tester, 2);

    expect(find.text('Verifikasi Sesi'), findsOneWidget);
  });

  /// Sesi yang sudah berjalan dilanjutkan tepat pada langkahnya, dan
  /// yang menentukan langkah itu adalah `statusProcess` dari
  /// `manage-sessioncode` — bukan status konektor.
  group('lanjutan sesi mengikuti statusProcess', () {
    /// Order yang belum dibayar dikembalikan ke konfirmasi dulu —
    /// pengguna perlu melihat lagi apa yang akan dibayarnya.
    testWidgets('1 belum bayar membuka Konfirmasi Pengisian', (tester) async {
      await _tapConnector(tester, 3, statusProcess: 1);
      await _verify(tester);

      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);
    });

    /// Tahap 0 berarti konektornya baru dipesan dan ordernya belum ada
    /// — keadaan yang tertinggal bila aplikasi ditutup tepat setelah
    /// konektor dipilih. Pengguna dikembalikan ke langkah yang memang
    /// mengikuti pemesanan, bukan ke konfirmasi yang tidak punya order.
    testWidgets('0 pemesanan membuka Kode Sesi', (tester) async {
      await _tapConnector(tester, 0, statusProcess: 0);
      await _verify(tester);

      expect(find.text('Kode Sesi'), findsOneWidget);
      // Kode dan tenggatnya yang lama, bukan pemesanan baru.
      expect(find.text('29'), findsOneWidget);
      expect(find.text('Lanjutkan'), findsOneWidget);
    });

    /// Ingatan pemesanan hilang saat aplikasi ditutup. Halaman Kode
    /// Sesi yang dilanjutkan memasangnya kembali dari
    /// `manage-sessioncode`, jadi pembatalannya benar-benar terkirim —
    /// tanpa itu konektornya tertahan sampai tenggatnya lewat.
    testWidgets('pemesanan yang dilanjutkan masih bisa dibatalkan', (
      tester,
    ) async {
      final stub = await _tapConnector(tester, 0, statusProcess: 0);
      await _verify(tester);
      expect(find.text('Kode Sesi'), findsOneWidget);

      await tester.tap(find.text('Batalkan Transaksi'));
      await settleFrames(tester);
      await tester.tap(find.text('Batalkan'));
      await settleFrames(tester);

      final cancel = stub.to('/cancelled-connector').single;
      expect((cancel.data as Map)['reservationId'], 'RESV-9');
      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    testWidgets('2 membuka Hubungkan Konektor', (tester) async {
      await _tapConnector(tester, 3, statusProcess: 2);
      await _verify(tester);

      expect(find.textContaining('Konektor Terhubung'), findsNothing);
      expect(find.text('Hubungkan Konektor'), findsOneWidget);
    });

    testWidgets('3 membuka Sedang Mengisi', (tester) async {
      await _tapConnector(tester, 2, statusProcess: 3);
      await _verify(tester);

      expect(find.text('Sedang Mengisi'), findsOneWidget);
    });

    testWidgets('4 membuka Pengisian Selesai', (tester) async {
      await _tapConnector(tester, 2, statusProcess: 4);
      await _verify(tester);

      expect(find.text('Pengisian Selesai'), findsOneWidget);
    });

    /// Tanpa rincian order yang bisa dibaca, konfirmasi tidak punya
    /// angka untuk ditampilkan — pengguna diantar ke pembayaran.
    testWidgets('tanpa rincian order jatuh ke Pembayaran', (tester) async {
      await _tapConnector(tester, 0, statusProcess: 1, orderReadable: false);
      await _verify(tester);

      expect(find.text('Pembayaran'), findsOneWidget);
    });
  });

  /// "Selesai" ikut ke layar pemantauan; `ongoing-kwh` yang menentukan,
  /// dan begitu ia melaporkan selesai halaman itu berpindah sendiri ke
  /// rincian akhir.

  /// "Tidak tersedia" diperlakukan sama dengan angka yang tak dikenal:
  /// konektornya tidak bisa ditekan sama sekali.
  testWidgets('status 4 tidak bisa ditekan', (tester) async {
    await _tapConnector(tester, 4);

    expect(find.text('Daftar Konektor'), findsOneWidget);
    expect(find.text('Verifikasi Sesi'), findsNothing);
  });

  testWidgets('status tak dikenal membuat konektornya tidak bisa ditekan', (
    tester,
  ) async {
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(9))),
    );

    await tester.pumpWidget(SPKLUApp(repository: repo));
    await tester.pumpAndSettle();

    // Kartunya tetap bisa dibuka — status baru ketahuan setelah
    // ditanyakan, jadi daftar tidak bisa mematikannya lebih dulu.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();

    expect(find.text('Daftar Konektor'), findsOneWidget);
    expect(find.text('Tidak Tersedia'), findsOneWidget);

    await tester.tap(find.text('Gun 1'));
    await settleFrames(tester);

    // Tidak ke mana-mana: sheet-nya masih terbuka.
    expect(find.text('Daftar Konektor'), findsOneWidget);
    expect(find.text('Pilih kWh'), findsNothing);
  });

  /// Sesi yang dilanjutkan tidak melewati push-order maupun
  /// payment-billing, jadi tenggatnya hanya bisa datang dari
  /// `manage-sessioncode`. Tanpa itu hitung mundurnya cuma angka
  /// cadangan sepuluh menit yang dikarang aplikasi.
  group('hitung mundur sesi lanjutan', () {
    testWidgets('memakai sessionExpiredTime dari manage-sessioncode', (
      tester,
    ) async {
      final expiry = DateTime.now().toUtc().add(const Duration(minutes: 7));

      await _tapConnector(
        tester,
        2,
        statusProcess: 2,
        sessionExpiredTime: expiry.toIso8601String(),
      );
      await _verify(tester);

      expect(find.text('Hubungkan Konektor'), findsOneWidget);
      final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
      expect(pill.remaining.inSeconds, closeTo(420, 3));
    });

    /// Halaman Pembayaran pada sesi lanjutan tidak punya jawaban
    /// `push-order` untuk dibaca; tenggatnya dibaca ulang dari
    /// `charging/detail`, yang mengirim tenggat order yang sama.
    testWidgets('Pembayaran memakai sessionExpiredTime dari charging/detail', (
      tester,
    ) async {
      final detail = DateTime.now().toUtc().add(const Duration(minutes: 4));

      await _tapConnector(
        tester,
        0,
        statusProcess: 1,
        detailExpiredTime: detail.toIso8601String(),
        // Tenggat manage-sessioncode sengaja dibuat jauh berbeda supaya
        // terlihat mana yang dipakai.
        sessionExpiredTime: DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 9))
            .toIso8601String(),
      );
      await _verify(tester);
      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);

      await tester.tap(find.text('Konfirmasi & Bayar'));
      await settleFrames(tester);

      final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
      expect(pill.remaining.inSeconds, closeTo(240, 3));
    });

    /// `sessionExpiredTime` di `charging/detail` null saat pemesanannya
    /// sudah tidak memegang tenggat; yang dipakai lalu tenggat dari
    /// `manage-sessioncode`.
    testWidgets('Pembayaran jatuh ke tenggat manage-sessioncode', (
      tester,
    ) async {
      final session = DateTime.now().toUtc().add(const Duration(minutes: 6));

      await _tapConnector(
        tester,
        0,
        statusProcess: 1,
        sessionExpiredTime: session.toIso8601String(),
      );
      await _verify(tester);

      await tester.tap(find.text('Konfirmasi & Bayar'));
      await settleFrames(tester);

      final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
      expect(pill.remaining.inSeconds, closeTo(360, 3));
    });

    testWidgets('tanpa tenggat jatuh ke cadangan sepuluh menit', (
      tester,
    ) async {
      await _tapConnector(tester, 2, statusProcess: 2);
      await _verify(tester);

      final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
      expect(pill.remaining, const Duration(minutes: 10));
    });
  });
}
