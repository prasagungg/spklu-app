import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/api_config.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/pages/api_config_page.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/widgets/primary_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menjawab `/list` dengan [status] HTTP yang diminta, supaya uji
/// koneksi di halaman konfigurasi bisa dibuat berhasil atau gagal.
class _Stub extends Interceptor {
  _Stub({this.fail = false});

  final bool fail;
  final List<String> baseUrls = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    baseUrls.add(options.baseUrl);

    if (fail) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {
          'responseCode': '00',
          'responseMessage': 'Success',
          'data': {'chargePoints': <Map<String, dynamic>>[]},
        },
      ),
    );
  }
}

/// Membangun halaman konfigurasi di atas scope yang memakai [stub].
Future<void> _pumpPage(WidgetTester tester, _Stub stub) async {
  final dio = Dio()..interceptors.add(stub);

  await tester.pumpWidget(
    ChargingScope(
      repository: ChargePointRepository(client: ApiClient.withDio(dio)),
      child: const MaterialApp(home: ApiConfigPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Tiap test mulai dari alamat bawaan, bukan sisa test sebelumnya.
    ApiConfig.apply(Env.apiBaseUrl);
  });

  testWidgets('isian awal memakai alamat yang sedang dipakai',
      (tester) async {
    await _pumpPage(tester, _Stub());

    final field = tester.widget<TextField>(
      find.byKey(ApiConfigPage.fieldKey),
    );
    expect(field.controller!.text, Env.apiBaseUrl);
  });

  testWidgets('alamat tanpa skema ditampilkan lengkap sebagai http',
      (tester) async {
    await _pumpPage(tester, _Stub());

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '192.168.1.10:8080',
    );
    await tester.pump();

    expect(
      find.text('Akan memanggil http://192.168.1.10:8080/list'),
      findsOneWidget,
    );
  });

  testWidgets('Hubungkan memakai alamat baru lalu membuka daftar charge box',
      (tester) async {
    final stub = _Stub();
    await _pumpPage(tester, stub);

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '10.0.2.2:8080',
    );
    await tester.pump();
    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();

    // Uji koneksi dan pemuatan daftar sesudahnya sama-sama menembak
    // alamat yang baru diketik, bukan bawaan.
    expect(stub.baseUrls, isNotEmpty);
    expect(stub.baseUrls, everyElement('http://10.0.2.2:8080'));
    expect(ApiConfig.baseUrl, 'http://10.0.2.2:8080');
    expect(find.byType(ChargeBoxPage), findsOneWidget);
  });

  testWidgets('alamat tersimpan sehingga terpakai lagi setelah dibuka ulang',
      (tester) async {
    await _pumpPage(tester, _Stub());

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '192.168.4.21:9000',
    );
    await tester.pump();
    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();

    // Meniru aplikasi dibuka lagi: nilai di memori dikembalikan ke
    // bawaan, lalu dibaca ulang dari penyimpanan.
    ApiConfig.apply(Env.apiBaseUrl);
    expect(await ApiConfig.restore(), 'http://192.168.4.21:9000');
  });

  testWidgets('alamat yang tidak bisa dihubungi tidak melanjutkan',
      (tester) async {
    await _pumpPage(tester, _Stub(fail: true));

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '192.168.9.9:1234',
    );
    await tester.pump();
    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();

    expect(find.byType(ChargeBoxPage), findsNothing);
    expect(
      find.text('Tidak dapat terhubung ke server. Periksa jaringan Anda.'),
      findsOneWidget,
    );
  });

  testWidgets('alamat yang gagal diuji tidak ikut tersimpan', (tester) async {
    await _pumpPage(tester, _Stub(fail: true));

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '192.168.9.9:1234',
    );
    await tester.pump();
    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('spklu_api_base_url'), isNull);
  });

  testWidgets('Lanjut Tanpa Uji masuk walau controller sedang mati',
      (tester) async {
    final stub = _Stub(fail: true);
    await _pumpPage(tester, stub);

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '192.168.9.9:1234',
    );
    await tester.pump();
    await tester.tap(find.text('Lanjut Tanpa Uji'));
    await tester.pumpAndSettle();

    expect(find.byType(ChargeBoxPage), findsOneWidget);
    expect(ApiConfig.baseUrl, 'http://192.168.9.9:1234');
  });

  testWidgets('kolom kosong mematikan kedua tombol', (tester) async {
    await _pumpPage(tester, _Stub());

    await tester.enterText(find.byKey(ApiConfigPage.fieldKey), '   ');
    await tester.pump();

    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<SecondaryButton>(find.byType(SecondaryButton)).onPressed,
      isNull,
    );
  });

  testWidgets('tombol di header daftar charge box kembali ke konfigurasi',
      (tester) async {
    await _pumpPage(tester, _Stub());

    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();
    expect(find.byType(ChargeBoxPage), findsOneWidget);

    await tester.tap(find.byKey(ChargeBoxPage.configKey));
    await tester.pumpAndSettle();

    expect(find.byType(ApiConfigPage), findsOneWidget);
    // Konfigurasi menggantikan daftar, bukan menumpuk di atasnya,
    // supaya "Kembali ke Halaman Awal" tetap memulangkan ke daftar.
    expect(find.byType(ChargeBoxPage), findsNothing);
  });
}
