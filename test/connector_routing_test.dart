import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

import 'fixtures.dart';
import 'flow_helpers.dart';

class _Stub extends Interceptor {
  _Stub(this.status, {this.statusProcess = 3, this.orderReadable = true});

  /// Status konektor pada `detail-chargerbox` — menentukan bisa
  /// ditekan atau tidak, dan perlu verifikasi kode sesi atau tidak.
  final int status;

  /// Tahap transaksi pada `manage-sessioncode` — menentukan halaman
  /// tempat sesi yang sudah berjalan dilanjutkan.
  final int statusProcess;

  /// Rincian order bisa dibaca lewat `charging/detail`. Dimatikan untuk
  /// menguji jalan mundurnya.
  final bool orderReadable;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/transaction/charging/ongoing-kwh' => ongoingKwhResponse(status: 3),
          '/transaction/charging/detail' =>
            orderReadable ? chargingDetailResponse() : okResponse,
          // Status sebenarnya datang dari sini, bukan dari daftar.
          '/detail-chargerbox' => chargeBoxDetailResponse(
            connectors: [connectorJson(status: status)],
          ),
          '/booked-connector' => bookingResponse(),
          '/manage-sessioncode' => sessionCodeResponse(
            statusProcess: statusProcess,
          ),
          // Kabelnya dianggap sudah terpasang; penungguannya
          // diuji tersendiri di connector_detection_poll_test.
          '/check-status-connector' => connectorStatusResponse(),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/transaction/payment-billing' => paymentBillingResponse(),
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
Future<void> _tapConnector(
  WidgetTester tester,
  int status, {
  int statusProcess = 3,
  bool orderReadable = true,
}) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(
      Dio()
        ..interceptors.add(
          _Stub(
            status,
            statusProcess: statusProcess,
            orderReadable: orderReadable,
          ),
        ),
    ),
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
    expect(find.text('Pilih Nominal'), findsOneWidget);
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

    testWidgets('0 pemesanan membuka Konfirmasi Pengisian', (tester) async {
      await _tapConnector(tester, 0, statusProcess: 0);
      await _verify(tester);

      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);
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
      await _tapConnector(tester, 0, statusProcess: 0, orderReadable: false);
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
    expect(find.text('Pilih Nominal'), findsNothing);
  });
}
