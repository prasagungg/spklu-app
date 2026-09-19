import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

class _Stub extends Interceptor {
  _Stub(this.status);

  final String status;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: options.path == '/progress'
            ? const {
                'responseCode': '00',
                'responseMessage': 'Success',
                'data': {
                  'chargePointId': 'SIM-456',
                  'connectorId': 1,
                  'transactionId': 42,
                  'state': 'charging',
                  'connectorStatus': 'Charging',
                  'percent': 30.0,
                  'energyWh': 500,
                  'powerW': 12000,
                  'durationSeconds': 60,
                },
              }
            : {
                'responseCode': '00',
                'responseMessage': 'Success',
                'data': {
                  'chargePoints': [
                    {
                      'id': 'SIM-456',
                      'connectors': [
                        {
                          'id': 1,
                          'status': status,
                          'errorCode': 'NoError',
                          'session': status == 'Charging'
                              ? {
                                  'chargePointId': 'SIM-456',
                                  'connectorId': 1,
                                  'transactionId': 42,
                                  'state': 'charging',
                                  'energyWh': 500,
                                  'powerW': 12000,
                                  'percent': 30.0,
                                  'durationSeconds': 60,
                                }
                              : null,
                        },
                      ],
                    },
                  ],
                },
              },
        statusCode: 200,
      ),
    );
  }
}

Future<void> _tapConnector(WidgetTester tester, String status) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(_Stub(status))),
  );
  await tester.pumpWidget(
    SPKLUApp(repository: repo, home: const ChargeBoxPage()),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('01'));
  await tester.pumpAndSettle();
  // Kartu konektor di dalam bottom sheet.
  await tester.tap(find.text('Konektor 1'));
  // Sheet menutup lalu rute baru didorong; keduanya beranimasi.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 600));

  // Konektor selain "Available" dijaga layar Verifikasi Sesi.
  if (status != 'Available') {
    expect(find.text('Verifikasi Sesi'), findsOneWidget);
    await enterPin(tester);
  }
}

/// Mengetik PIN sesi lalu menekan Verifikasi.
Future<void> enterPin(WidgetTester tester, [String pin = '00']) async {
  for (final digit in pin.split('')) {
    // Keypad bisa berada di luar layar pada ukuran uji, jadi
    // digulirkan dulu sebelum ditekan.
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
}

void main() {
  testWidgets('Available membuka alur pembelian', (tester) async {
    await _tapConnector(tester, 'Available');
    expect(find.text('Pilih Nominal'), findsOneWidget);
  });

  testWidgets('Preparing juga membuka alur pembelian, sama seperti Available',
      (tester) async {
    await _tapConnector(tester, 'Preparing');
    expect(find.text('Pilih Nominal'), findsOneWidget);
    expect(find.text('Sedang Mengisi'), findsNothing);
  });

  testWidgets('Charging langsung ke layar pemantauan', (tester) async {
    await _tapConnector(tester, 'Charging');
    expect(find.text('Sedang Mengisi'), findsOneWidget);
    expect(find.text('Pilih Nominal'), findsNothing);
  });
}
