import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/charging_finished_page.dart';
import 'package:kossotrik/pages/charging_status_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fixtures.dart';
import 'flow_helpers.dart';

/// Menahan polling pertama sampai test melepasnya, lalu menjawab
/// "selesai" — meniru jawaban yang tiba setelah pengguna menekan
/// Akhiri Pengisian.
class _Stub extends Interceptor {
  final gate = Completer<void>();
  bool _held = false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.path == '/transaction/charging/ongoing-kwh') {
      if (!_held) {
        _held = true;
        await gate.future;
      }
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          data: ongoingKwhResponse(status: 4),
          statusCode: 200,
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: okResponse,
        statusCode: 200,
      ),
    );
  }
}

Future<_Stub> _pump(WidgetTester tester) async {
  final stub = _Stub();
  final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

  await tester.pumpWidget(
    ChargingScope(
      repository: ChargePointRepository(
        client: ApiClient.withDio(Dio()..interceptors.add(stub)),
      ),
      child: MaterialApp(
        theme: AppTheme.build(),
        home: ChargingStatusPage(
          session: ChargingSession(
            chargeBox: box,
            connector: box.connectors.single,
            sessionCode: '29',
            reference: '81067',
            createdAt: DateTime(2026),
            orderId: 'ORDER-1',
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return stub;
}

void main() {
  testWidgets(
    'jawaban polling yang telat tidak menggusur layar verifikasi',
    (tester) async {
      final stub = await _pump(tester);

      // Polling pertama berangkat dan tertahan di stub.
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Akhiri Pengisian'));
      await settleFrames(tester);
      expect(find.text('Verifikasi Sesi'), findsOneWidget);

      // Jawaban "selesai" baru tiba sekarang — sesudah pengguna masuk
      // alur mengakhiri sesi.
      stub.gate.complete();
      await settleFrames(tester);

      // Halaman verifikasi harus tetap berdiri, dan rincian akhir belum
      // boleh muncul.
      expect(find.text('Verifikasi Sesi'), findsOneWidget);
      expect(find.byType(ChargingFinishedPage), findsNothing);
    },
  );

  testWidgets('rincian akhir hanya dibuka sekali', (tester) async {
    final stub = await _pump(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Akhiri Pengisian'));
    await settleFrames(tester);

    stub.gate.complete();
    await settleFrames(tester);

    await enterSessionCode(tester, '29');
    // Pembacaan energi akhir menunggu sedetik per percobaan.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await settleFrames(tester);

    // Satu halaman, bukan dua yang saling menumpuk — tumpukan itulah
    // yang membuat tombol "Kembali ke Halaman Awal" dan tombol Home
    // tidak bisa ditekan.
    expect(find.byType(ChargingFinishedPage), findsOneWidget);
    expect(find.text('Kembali ke Halaman Awal'), findsOneWidget);
    // Ditekan tanpa melempar; di test ini rincian akhir kebetulan rute
    // pertama, jadi popUntil memang tidak memulangkan ke mana pun.
    await tester.tap(find.text('Kembali ke Halaman Awal'));
    await settleFrames(tester);
  });
}
