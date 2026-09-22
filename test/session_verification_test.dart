import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/session_check.dart';
import 'package:kossotrik/pages/session_verification_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fixtures.dart';

/// Menjawab `POST /manage-sessioncode`; bisa dibuat menolak.
class _Stub extends Interceptor {
  _Stub({this.errorCode, this.statusProcess = 2, this.orderId = 'ORDER-9'});

  final String? errorCode;
  final int statusProcess;
  final String orderId;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (errorCode != null) {
      handler.reject(
        DioException.badResponse(
          statusCode: 404,
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 404,
            data: {
              'responseCode': errorCode,
              'responseMessage': 'Transaction Not Found',
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
        data: sessionCodeResponse(
          statusProcess: statusProcess,
          orderId: orderId,
        ),
      ),
    );
  }
}

SessionCheck? lastResult;

/// Membuka halaman. [stub] null berarti mode offline — tanpa backend,
/// kodenya dibandingkan dengan [expectedCode].
Future<void> _open(
  WidgetTester tester, {
  _Stub? stub,
  String? expectedCode,
}) async {
  lastResult = null;

  final page = Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        lastResult = await Navigator.of(context).push<SessionCheck>(
          MaterialPageRoute<SessionCheck>(
            builder: (_) => SessionVerificationPage(
              chargeBoxId: 'CB-SMR-01',
              connectorId: 1,
              expectedCode: expectedCode,
            ),
          ),
        );
      },
      child: const Text('buka'),
    ),
  );

  await tester.pumpWidget(
    stub == null
        ? MaterialApp(theme: AppTheme.build(), home: page)
        : ChargingScope(
            repository: ChargePointRepository(
              client: ApiClient.withDio(Dio()..interceptors.add(stub)),
            ),
            child: MaterialApp(theme: AppTheme.build(), home: page),
          ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String digit) async {
  final key = find.widgetWithText(InkWell, digit).last;
  await tester.ensureVisible(key);
  await tester.pump();
  await tester.tap(key);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    await _press(tester, digit);
  }
  final button = find.widgetWithText(InkWell, 'Verifikasi');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Verifikasi mati sampai dua digit terisi', (tester) async {
    await _open(tester);

    expect(find.text('Verifikasi Sesi'), findsOneWidget);
    expect(find.text('Masukkan 2 digit kode sesi'), findsOneWidget);

    await _press(tester, '0');
    final button = find.widgetWithText(InkWell, 'Verifikasi');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();

    // Satu digit belum cukup — halaman tidak boleh tertutup.
    expect(find.text('Verifikasi Sesi'), findsOneWidget);
  });

  group('diperiksa backend', () {
    testWidgets('kode dikirim ke manage-sessioncode', (tester) async {
      final stub = _Stub();
      await _open(tester, stub: stub);

      await _enter(tester, '29');

      final call = stub.requests.single;
      expect(call.method, 'POST');
      expect(call.path, '/manage-sessioncode');
      expect(call.data, {
        'chargeBoxId': 'CB-SMR-01',
        'connectorId': '1',
        'sessionCode': '29',
      });
    });

    /// statusProcess-nya ikut terbawa; halaman Hubungkan Konektor
    /// memakai angka itu untuk tahu nozzle sudah tercolok.
    testWidgets('kode benar menutup halaman dengan hasil pemeriksaan',
        (tester) async {
      await _open(tester, stub: _Stub(statusProcess: 3, orderId: 'ORDER-9'));

      await _enter(tester, '29');

      expect(lastResult, isNotNull);
      expect(lastResult!.sessionCode, '29');
      expect(lastResult!.statusProcess, 3);
      expect(lastResult!.isPluggedIn, isTrue);
      // Ordernya ikut terbawa, jadi sesi yang dibuka kembali bisa
      // dipantau dan dihentikan.
      expect(lastResult!.orderId, 'ORDER-9');
      expect(find.text('Verifikasi Sesi'), findsNothing);
    });

    testWidgets('kode yang ditolak menjelaskan sebabnya', (tester) async {
      await _open(tester, stub: _Stub(errorCode: '21'));

      await _enter(tester, '99');

      expect(find.text('Verifikasi Sesi'), findsOneWidget);
      expect(
        find.text('Kode sesi tidak cocok, atau sesinya sudah berakhir'),
        findsOneWidget,
      );
      expect(lastResult, isNull);
    });

    testWidgets('kode yang ditolak mengosongkan isian', (tester) async {
      await _open(tester, stub: _Stub(errorCode: '21'));

      await _enter(tester, '12');

      // Isian dikosongkan, jadi angka 1 dan 2 hanya tersisa di keypad.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('mode offline', () {
    testWidgets('kode yang cocok menutup halaman', (tester) async {
      await _open(tester, expectedCode: '29');

      await _enter(tester, '29');

      expect(lastResult, isNotNull);
      expect(find.text('Verifikasi Sesi'), findsNothing);
    });

    testWidgets('kode salah memberi tahu', (tester) async {
      await _open(tester, expectedCode: '29');

      await _enter(tester, '12');

      expect(find.text('Kode sesi salah, coba lagi'), findsOneWidget);
    });
  });

  testWidgets('tombol hapus menghapus digit terakhir', (tester) async {
    await _open(tester);

    await _press(tester, '1');
    await _press(tester, '2');
    // Dua digit terisi: angka 1 muncul di kotak dan di keypad.
    expect(find.text('1'), findsNWidgets(2));

    final erase = find.byKey(SessionVerificationPage.eraseKey);
    await tester.ensureVisible(erase);
    await tester.pump();
    await tester.tap(erase);
    await tester.pump();

    // Digit terakhir (2) hilang dari kotak.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('Kembali menutup halaman tanpa hasil', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();

    expect(lastResult, isNull);
  });
}
