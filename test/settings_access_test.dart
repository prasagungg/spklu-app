import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/pages/settings_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

import 'fixtures.dart';

/// Menjawab `POST /login`, dan mencatat apa yang dikirim ke sana.
class _LoginStub extends Interceptor {
  _LoginStub({this.accept = true});

  final bool accept;
  final List<Object?> logins = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/login') logins.add(options.data);

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path == '/login' && !accept
            ? {
                'responseCode': '18',
                'responseMessage': 'Username atau password salah',
              }
            : okResponse,
      ),
    );
  }
}

/// Halaman awal di atas scope yang memakai [stub], supaya gerbang
/// Pengaturan benar-benar menembak backend.
Future<_LoginStub> _pumpOnline(
  WidgetTester tester, {
  bool accept = true,
}) async {
  final stub = _LoginStub(accept: accept);

  await tester.pumpWidget(
    ChargingScope(
      repository: ChargePointRepository(
        client: ApiClient.withDio(Dio()..interceptors.add(stub)),
      ),
      child: MaterialApp(
        theme: AppTheme.build(),
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return stub;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mengetuk logo [times] kali beruntun.
Future<void> tapLogo(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(PageScaffold.logKey));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle();
}

Future<void> login(
  WidgetTester tester, {
  String username = 'EC-00001-2',
  required String password,
}) async {
  await tester.enterText(
    find.byKey(const Key('login-username-field')),
    username,
  );
  await tester.enterText(
    find.byKey(const Key('login-password-field')),
    password,
  );
  await tester.pump();
  await tester.tap(find.text('Masuk'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empat ketukan belum membuka apa pun', (tester) async {
    await _pump(tester);

    await tapLogo(tester, 4);

    expect(find.text('Akses Pengaturan'), findsNothing);
  });

  testWidgets('lima ketukan meminta password', (tester) async {
    await _pump(tester);

    await tapLogo(tester, 5);

    expect(find.text('Akses Pengaturan'), findsOneWidget);
    // Belum boleh masuk sebelum passwordnya benar.
    expect(find.byType(SettingsPage), findsNothing);
  });

  /// Tanpa [ChargingScope] tidak ada backend untuk ditanya — demo dan
  /// test. Produksi selalu punya scope, jadi jalur ini tidak pernah
  /// lewat di perangkat sungguhan; gerbang sungguhannya `POST /login`,
  /// diuji tersendiri di bawah.
  testWidgets('tanpa backend, password lokal membuka Pengaturan', (
    tester,
  ) async {
    await _pump(tester);
    await tapLogo(tester, 5);

    await login(tester, password: Env.settingsPassword);

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Kelola perangkat dan pengaturan SPKLU'), findsOneWidget);
    expect(find.text('Konfigurasi SAM Card'), findsOneWidget);
    expect(find.text('Tes Transaksi'), findsOneWidget);
    expect(find.textContaining('Versi'), findsOneWidget);
  });

  testWidgets('tanpa backend, password salah ditolak', (tester) async {
    await _pump(tester);
    await tapLogo(tester, 5);

    await login(tester, password: 'salah');

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Password salah. Coba lagi.'), findsOneWidget);
    expect(find.text('Akses Pengaturan'), findsOneWidget);
  });

  group('gerbangnya POST /login', () {
    testWidgets('amplop 00 membuka halaman Pengaturan', (tester) async {
      final stub = await _pumpOnline(tester);
      await tapLogo(tester, 5);

      await login(tester, password: 'EV@2026_EC-00001-2');

      expect(stub.logins, [
        {'username': 'EC-00001-2', 'password': 'EV@2026_EC-00001-2'},
      ]);
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    /// Alasan penolakannya datang dari backend, bukan tebakan aplikasi.
    testWidgets('amplop selain 00 menahan di modalnya', (tester) async {
      await _pumpOnline(tester, accept: false);
      await tapLogo(tester, 5);

      await login(tester, password: 'salah');

      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('Akses Pengaturan'), findsOneWidget);
      expect(find.text('Username atau password salah'), findsOneWidget);
    });

    /// Kredensial kosong tidak perlu dibawa ke backend untuk ditolak.
    testWidgets('tidak bisa masuk dengan kolom kosong', (tester) async {
      final stub = await _pumpOnline(tester);
      await tapLogo(tester, 5);

      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();

      expect(stub.logins, isEmpty);
      expect(find.text('Akses Pengaturan'), findsOneWidget);
    });
  });

  testWidgets('Batal menutup modal tanpa membuka pengaturan', (tester) async {
    await _pump(tester);
    await tapLogo(tester, 5);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Akses Pengaturan'), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
  });

  /// Ketukan yang berjauhan adalah sentuhan biasa, bukan rangkaian.
  testWidgets('ketukan yang lewat dari jendela waktu tidak menumpuk', (
    tester,
  ) async {
    await _pump(tester);

    await tapLogo(tester, 3);
    await tester.pump(const Duration(seconds: 3));
    await tapLogo(tester, 3);

    expect(find.text('Akses Pengaturan'), findsNothing);
  });
}
