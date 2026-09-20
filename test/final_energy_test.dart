import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub(this.progress);

  final Map<String, dynamic> Function() progress;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/list-chargerbox' => listResponse([
              chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01'),
            ]),
          '/booked-connector' => bookingResponse(),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/progress' => progress(),
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
    // Saat tombol ditekan energinya 3 Wh; charger masih menyalurkan
    // daya sampai akhirnya berhenti di 17 Wh.
    var state = 'charging';
    var energyWh = 3;

    final repo = ChargePointRepository(
      client: ApiClient.withDio(
        Dio()
          ..interceptors.add(
            _Stub(() => progressResponse(state: state, energyWh: energyWh)),
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
    await tester.pumpAndSettle();
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await _settle(tester);

    reader.tap();
    await _settle(tester);
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

    expect(find.text('Sedang Mengisi'), findsOneWidget);

    // Polling pertama membawa 3 Wh.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('0,003 kWh'), findsOneWidget);

    await tester.tap(find.text('Akhiri Pengisian'));
    await _settle(tester);
    await tester.tap(find.text('Ya, Akhiri Pengisian'));

    // Charger berhenti dan melaporkan angka akhir yang lebih besar.
    state = 'finished';
    energyWh = 17;

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
