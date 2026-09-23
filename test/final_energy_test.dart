import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';
import 'flow_helpers.dart';

class _Stub extends Interceptor {
  _Stub(this.progress);

  final Map<String, dynamic> Function() progress;

  /// Setelah perintah start, konektornya melapor sedang mengisi.
  bool _charging = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/transaction/charging/start') _charging = true;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/list-chargerbox' => listResponse([
              chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01'),
            ]),
          '/booked-connector' => bookingResponse(),
          '/manage-sessioncode' => sessionCodeResponse(),
          '/detail-chargerbox' => chargeBoxDetailResponse(
              connectors: [connectorJson(status: _charging ? 3 : 1)],
            ),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/transaction/payment-billing' => paymentBillingResponse(),
          '/transaction/charging/ongoing-kwh' => progress(),
          _ => okResponse,
        },
        statusCode: 200,
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('kWh akhir diambil dari /progress terakhir, bukan saat ditekan',
      (tester) async {
    // Saat tombol ditekan energinya 0,003 kWh; charger masih
    // menyalurkan daya sampai akhirnya berhenti di 0,017 kWh.
    var status = 3;
    var charged = 0.003;

    final repo = ChargePointRepository(
      client: ApiClient.withDio(
        Dio()
          ..interceptors.add(
            _Stub(() => ongoingKwhResponse(status: status, charged: charged)),
          ),
      ),
    );
    final reader = FakeCardReader();

    await tester.pumpWidget(SPKLUApp(repository: repo, cardReader: reader));
    await tester.pumpAndSettle();

    // Alur pembelian sampai layar pemantauan.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await _settle(tester);

    reader.tap();
    await _settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Mulai Pengisian'));
    await _settle(tester);

    // Jeda deteksi konektor.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian').last);
    // /start berjalan async, jadi perlu beberapa pump agar futurenya
    // sempat selesai sebelum transisi halaman dihitung.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    // Kode sesi dari push-order ditunjukkan dulu; pemantauan dibuka
    // dengan kode itu dari daftar charge box.
    await reopenChargingSession(tester);
    expect(find.text('Sedang Mengisi'), findsOneWidget);

    // Polling pertama membawa 0,003 kWh.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('0,003 kWh'), findsOneWidget);

    await tester.tap(find.text('Akhiri Pengisian'));
    await _settle(tester);
    await tester.tap(find.text('Ya, Akhiri Pengisian'));

    // Charger berhenti dan melaporkan angka akhir yang lebih besar.
    status = 4;
    charged = 0.017;

    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pengisian Selesai'), findsOneWidget);
    // 17 Wh, bukan 3 Wh yang terbaca saat tombol ditekan.
    expect(find.text('0,017 kWh'), findsOneWidget);
    expect(find.text('0,003 kWh'), findsNothing);

    await tester.tap(find.text('Kembali ke Halaman Awal'));
    await tester.pumpAndSettle();
    expect(find.byType(ChargeBoxPage), findsOneWidget);
  });
}
