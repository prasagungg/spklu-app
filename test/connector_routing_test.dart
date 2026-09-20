import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub(this.status);

  final int status;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/progress' => progressResponse(),
          // Status sebenarnya datang dari sini, bukan dari daftar.
          '/status-konektor' => connectorStatusResponse(status: status),
          '/booked-connector' => bookingResponse(),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          _ => listResponse([
              chargeBoxJson(
                nama: 'CB-SMR-01',
                connectors: [connectorJson()],
              ),
            ]),
        },
        statusCode: 200,
      ),
    );
  }
}

/// Membuka bottom sheet lalu menekan konektor satu-satunya.
Future<void> _tapConnector(WidgetTester tester, int status) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(_Stub(status))),
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
  await tester.pumpAndSettle();
}

/// Konektor yang sudah diklaim orang lain menuntut kode sesi dulu.
Future<void> _verify(WidgetTester tester) async {
  expect(find.text('Verifikasi Sesi'), findsOneWidget);

  for (final digit in '00'.split('')) {
    final key = find.widgetWithText(InkWell, digit).last;
    await tester.ensureVisible(key);
    await tester.pump();
    await tester.tap(key);
    await tester.pump();
  }
  await tester.tap(find.text('Verifikasi'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('status 1 membuka alur pembelian tanpa verifikasi',
      (tester) async {
    await _tapConnector(tester, 1);

    expect(find.text('Verifikasi Sesi'), findsNothing);
    expect(find.text('Pilih Nominal'), findsOneWidget);
  });

  testWidgets('status 2 melanjutkan ke Hubungkan Konektor', (tester) async {
    await _tapConnector(tester, 2);
    await _verify(tester);

    expect(find.text('Hubungkan Konektor'), findsOneWidget);
  });

  testWidgets('status 3 membuka layar pemantauan', (tester) async {
    await _tapConnector(tester, 3);
    await _verify(tester);

    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  /// "Selesai" ikut ke layar pemantauan; `/progress` yang menentukan,
  /// dan begitu ia melaporkan `finished` halaman itu berpindah sendiri
  /// ke rincian akhir.
  testWidgets('status 4 juga lewat layar pemantauan', (tester) async {
    await _tapConnector(tester, 4);
    await _verify(tester);

    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  testWidgets('status tak dikenal membuat konektornya tidak bisa ditekan',
      (tester) async {
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(0))),
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
    await tester.pumpAndSettle();

    // Tidak ke mana-mana: sheet-nya masih terbuka.
    expect(find.text('Daftar Konektor'), findsOneWidget);
    expect(find.text('Pilih Nominal'), findsNothing);
  });
}
