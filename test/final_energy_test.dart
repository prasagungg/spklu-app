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
  _Stub(this.progress, {this.detail});

  final Map<String, dynamic> Function() progress;

  /// Jawaban `charging/detail`. Null berarti amplop kosong — yang
  /// dipakai test untuk memastikan angka pemantauan tidak tertimpa.
  final Map<String, dynamic> Function()? detail;

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
          // Kabelnya dianggap sudah terpasang; penungguannya
          // diuji tersendiri di connector_detection_poll_test.
          '/check-status-connector' => connectorStatusResponse(),
          '/detail-chargerbox' => chargeBoxDetailResponse(
            connectors: [connectorJson(status: _charging ? 2 : 1)],
          ),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/transaction/payment-billing' => paymentBillingResponse(),
          '/transaction/charging/ongoing-kwh' => progress(),
          '/transaction/charging/detail' => detail?.call() ?? okResponse,
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

/// Membeli satu sesi sampai layar pemantauan terbuka.
Future<void> _runUntilCharging(WidgetTester tester, _Stub stub) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );
  final reader = FakeCardReader();

  await tester.pumpWidget(SPKLUApp(repository: repo, cardReader: reader));
  await tester.pumpAndSettle();

  await tester.tap(find.text('01'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gun 1'));
  await passSessionCode(tester);
  // Tidak ada pilihan yang tercentang sejak awal.
  await tester.tap(find.text('10'));
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
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 600));

  await reopenChargingSession(tester);
  expect(find.text('Sedang Mengisi'), findsOneWidget);

  await endCharging(tester);
}

void main() {
  /// Angka penutup milik pembukuan backend: berapa yang benar-benar
  /// terpakai dan berapa yang dikembalikan tidak pernah bisa dijamin
  /// sama kalau aplikasi menghitungnya sendiri.
  testWidgets('rincian akhir diambil dari charging/detail', (tester) async {
    var status = 3;
    var charged = 0.0;

    final stub = _Stub(
      () => ongoingKwhResponse(
        orderId: 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
        status: status,
        charged: charged,
      ),
      detail: () => chargingDetailResponse(
        kwhPakai: 6.4,
        rpPesan: 25400,
        rpPakai: 16256,
        rpSisa: 9144,
      ),
    );
    await _runUntilCharging(tester, stub);

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
    // Angka dari backend menggantikan hasil pemantauan dan hitungan
    // lokal: 6,4 kWh terpakai, Rp16.256 dipakai, Rp9.144 kembali.
    expect(find.text('6,4 kWh'), findsOneWidget);
    expect(find.text('Rp25.400'), findsOneWidget);
    expect(find.text('Rp16.256'), findsOneWidget);
    expect(find.text('Rp9.144'), findsOneWidget);
  });

  testWidgets('kWh akhir diambil dari /progress terakhir, bukan saat ditekan', (
    tester,
  ) async {
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
    await tester.tap(find.text('10'));
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

    await endCharging(tester);

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
    // 17 Wh, bukan 3 Wh yang terbaca saat tombol ditekan. Stub ini
    // tidak menjawab `charging/detail`, jadi yang tampil memang angka
    // pemantauan terakhir — rincian dari backend diuji tersendiri.
    expect(find.text('0,017 kWh'), findsOneWidget);
    expect(find.text('0,003 kWh'), findsNothing);

    await tester.tap(find.text('Kembali ke Halaman Awal'));
    await tester.pumpAndSettle();
    expect(find.byType(ChargeBoxPage), findsOneWidget);
  });
}
