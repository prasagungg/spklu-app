import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

class _Stub extends Interceptor {
  _Stub(this.progress);

  final Map<String, dynamic> Function() progress;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/list' => _list,
          '/progress' => progress(),
          _ => _ok,
        },
        statusCode: 200,
      ),
    );
  }
}

const _ok = {'responseCode': '00', 'responseMessage': 'Success'};

const _list = {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargePoints': [
      {
        'id': 'SIM-456',
        'connectors': [
          {'id': 1, 'status': 'Charging', 'errorCode': 'NoError',
            'session': {
              'chargePointId': 'SIM-456',
              'connectorId': 1,
              'transactionId': 42,
              'state': 'charging',
              'energyWh': 3,
              'powerW': 12000,
              'percent': 10.0,
              'durationSeconds': 5,
            }},
        ],
      },
    ],
  },
};

Map<String, dynamic> _progress(String state, int energyWh) => {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePointId': 'SIM-456',
        'connectorId': 1,
        'transactionId': 42,
        'state': state,
        'connectorStatus': state == 'finished' ? 'Preparing' : 'Charging',
        'percent': 10.0,
        'energyWh': energyWh,
        'powerW': state == 'finished' ? null : 12000,
        'durationSeconds': 5,
        'stopReason': state == 'finished' ? 'Remote' : null,
        'stoppedAt': state == 'finished'
            ? '2026-09-17T20:58:35.135618667+07:00'
            : null,
      },
    };

void main() {
  testWidgets('kWh akhir diambil dari /progress terakhir, bukan saat ditekan',
      (tester) async {
    // Saat tombol ditekan energinya 3 Wh; charger masih menyalurkan
    // daya sampai akhirnya berhenti di 17 Wh.
    var state = 'charging';
    var energyWh = 3;

    final repo = ChargePointRepository(
      client: ApiClient.withDio(
        Dio()..interceptors.add(_Stub(() => _progress(state, energyWh))),
      ),
    );

    await tester.pumpWidget(SPKLUApp(repository: repo));
    await tester.pumpAndSettle();

    // Konektor sedang mengisi -> langsung ke layar pemantauan.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konektor 1'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 600));

    // Konektor sedang mengisi -> harus verifikasi kode sesi dulu.
    expect(find.text('Verifikasi Sesi'), findsOneWidget);
    for (final digit in '00'.split('')) {
      final key = find.widgetWithText(InkWell, digit).last;
      await tester.ensureVisible(key);
      await tester.pump();
      await tester.tap(key);
      await tester.pump();
    }
    await tester.tap(find.text('Verifikasi'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Sedang Mengisi'), findsOneWidget);
    // Angkanya langsung terisi dari sesi yang sudah dibawa /list —
    // tidak sempat menampilkan 0 kWh sambil menunggu polling pertama.
    expect(find.text('0,003 kWh'), findsOneWidget);
    expect(find.text('0,000 kWh'), findsNothing);

    await tester.tap(find.text('Akhiri Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
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
  });
}
