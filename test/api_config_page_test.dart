import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/services/signature_interceptor.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';
import 'package:kossotrik/pages/settings_page.dart';
import 'package:kossotrik/config/api_config.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/pages/api_config_page.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/widgets/primary_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Menjawab `POST /list-chargerbox`, supaya uji koneksi di halaman
/// konfigurasi bisa dibuat berhasil atau gagal.
class _Stub extends Interceptor {
  _Stub({this.fail = false});

  final bool fail;
  final List<String> baseUrls = [];

  /// Header `client-id` yang benar-benar terkirim, untuk memastikan
  /// kredensial yang baru diketik yang dipakai — bukan yang lama.
  final List<String> clientIds = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    baseUrls.add(options.baseUrl);
    clientIds.add('${options.headers['client-id']}');

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
        data: listResponse(const []),
      ),
    );
  }
}

/// Membangun halaman konfigurasi di atas scope yang memakai [stub].
Future<void> _pumpPage(WidgetTester tester, _Stub stub) async {
  final dio = Dio()
    ..interceptors.add(SignatureInterceptor())
    ..interceptors.add(stub);

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
    FlutterSecureStorage.setMockInitialValues({});
    // Tiap test mulai dari nilai bawaan, bukan sisa test sebelumnya.
    ApiConfig.apply(
      baseUrl: Env.apiBaseUrl,
      clientId: Env.apiClientId,
      secretKey: Env.apiSecretKey,
    );
  });

  group('kredensial penandatangan', () {
    /// Kredensialnya dulu ikut tertanam saat build. Sekarang operator
    /// bisa merotasinya di lapangan tanpa APK dibangun ulang.
    testWidgets('isian awalnya memakai yang sedang dipakai', (tester) async {
      ApiConfig.apply(clientId: 'edge-lapangan', secretKey: 'rahasia-lama');
      await _pumpPage(tester, _Stub());

      expect(
        tester
            .widget<TextField>(find.byKey(ApiConfigPage.clientIdKey))
            .controller
            ?.text,
        'edge-lapangan',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(ApiConfigPage.secretKey))
            .controller
            ?.text,
        'rahasia-lama',
      );
    });

    /// Layar kios ini berdiri di tempat umum.
    testWidgets('secret key tersamar sampai diminta terlihat', (tester) async {
      await _pumpPage(tester, _Stub());

      TextField secret() =>
          tester.widget<TextField>(find.byKey(ApiConfigPage.secretKey));

      expect(secret().obscureText, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(ApiConfigPage.clientIdKey))
            .obscureText,
        isFalse,
        reason: 'client-id bukan rahasia',
      );

      final eye = find.byIcon(Icons.visibility_outlined);
      await tester.ensureVisible(eye);
      await tester.pumpAndSettle();
      await tester.tap(eye);
      await tester.pump();

      expect(secret().obscureText, isFalse);
    });

    /// Tanda tangan dari kredensial kosong pasti ditolak backend, dan
    /// gagalnya baru ketahuan di halaman berikutnya.
    testWidgets('tidak bisa lanjut dengan kredensial kosong', (tester) async {
      await _pumpPage(tester, _Stub());

      PrimaryButton connect() => tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Hubungkan'),
      );
      expect(connect().onPressed, isNotNull);

      await tester.enterText(find.byKey(ApiConfigPage.secretKey), '');
      await tester.pump();
      expect(connect().onPressed, isNull);

      await tester.enterText(find.byKey(ApiConfigPage.secretKey), 'rahasia');
      await tester.enterText(find.byKey(ApiConfigPage.clientIdKey), '');
      await tester.pump();
      expect(connect().onPressed, isNull);
    });

    /// Kredensial yang baru diketik harus sudah dipakai oleh uji
    /// koneksinya sendiri — kalau tidak, yang diuji kredensial lama.
    testWidgets('yang diketik langsung menandatangani request', (tester) async {
      final stub = _Stub();
      await _pumpPage(tester, stub);

      await tester.enterText(
        find.byKey(ApiConfigPage.fieldKey),
        '10.0.2.2:8080',
      );
      await tester.enterText(
        find.byKey(ApiConfigPage.clientIdKey),
        'edge-baru',
      );
      await tester.enterText(
        find.byKey(ApiConfigPage.secretKey),
        'rahasia-baru',
      );
      await tester.pump();
      await tester.tap(find.text('Hubungkan'));
      await tester.pumpAndSettle();

      expect(ApiConfig.clientId, 'edge-baru');
      expect(ApiConfig.secretKey, 'rahasia-baru');
      // Halaman berikutnya memuat daftarnya lagi, jadi bisa lebih dari
      // satu request — yang penting semuanya memakai kredensial baru.
      expect(stub.clientIds, isNotEmpty);
      expect(stub.clientIds.every((id) => id == 'edge-baru'), isTrue);
    });

    /// Tersimpan terenkripsi, dan terbaca lagi setelah aplikasi ditutup.
    testWidgets('diingat dan dipulihkan setelah restart', (tester) async {
      await _pumpPage(tester, _Stub());

      await tester.enterText(find.byKey(ApiConfigPage.clientIdKey), 'edge-pln');
      await tester.enterText(
        find.byKey(ApiConfigPage.secretKey),
        'kunci-lapangan',
      );
      await tester.pump();
      await tester.tap(find.text('Lanjut Tanpa Uji'));
      await tester.pumpAndSettle();

      // Aplikasi dimulai ulang: nilainya kembali ke bawaan build, lalu
      // dipulihkan dari penyimpanan.
      ApiConfig.apply(clientId: Env.apiClientId, secretKey: Env.apiSecretKey);
      await ApiConfig.restore();

      expect(ApiConfig.clientId, 'edge-pln');
      expect(ApiConfig.secretKey, 'kunci-lapangan');
    });
  });

  testWidgets('isian awal memakai alamat yang sedang dipakai', (tester) async {
    await _pumpPage(tester, _Stub());

    final field = tester.widget<TextField>(find.byKey(ApiConfigPage.fieldKey));
    expect(field.controller!.text, Env.apiBaseUrl);
  });

  testWidgets('alamat tanpa skema ditampilkan lengkap sebagai http', (
    tester,
  ) async {
    await _pumpPage(tester, _Stub());

    await tester.enterText(
      find.byKey(ApiConfigPage.fieldKey),
      '192.168.1.10:8080',
    );
    await tester.pump();

    expect(
      find.text('Akan memanggil http://192.168.1.10:8080/list-chargerbox'),
      findsOneWidget,
    );
  });

  testWidgets('Hubungkan memakai alamat baru lalu membuka daftar charge box', (
    tester,
  ) async {
    final stub = _Stub();
    await _pumpPage(tester, stub);

    await tester.enterText(find.byKey(ApiConfigPage.fieldKey), '10.0.2.2:8080');
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

  testWidgets('alamat tersimpan sehingga terpakai lagi setelah dibuka ulang', (
    tester,
  ) async {
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
    ApiConfig.apply(baseUrl: Env.apiBaseUrl);
    expect(await ApiConfig.restore(), 'http://192.168.4.21:9000');
  });

  testWidgets('alamat yang tidak bisa dihubungi tidak melanjutkan', (
    tester,
  ) async {
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

  testWidgets('Lanjut Tanpa Uji masuk walau controller sedang mati', (
    tester,
  ) async {
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

  /// Konfigurasi Server tidak lagi punya tombol di header daftar; ia
  /// dibuka dari halaman Pengaturan.
  testWidgets('dibuka dari kartu di halaman Pengaturan', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SettingsPage.serverKey));
    await tester.pumpAndSettle();

    expect(find.byType(ApiConfigPage), findsOneWidget);
    // Menumpuk di atas Pengaturan, jadi ada tempat untuk pulang.
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(HomeButton), findsWidgets);
  });

  /// Alamat yang berhasil dipasang memulangkan ke daftar charge box,
  /// yang memuat ulang dirinya dengan alamat baru itu.
  testWidgets('berhasil menghubungkan memulangkan ke daftar', (tester) async {
    await _pumpPage(tester, _Stub());

    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();

    expect(find.byType(ChargeBoxPage), findsOneWidget);
    expect(find.byType(ApiConfigPage), findsNothing);
  });
}
