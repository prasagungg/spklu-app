import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/pages/master_charge_box_page.dart';
import 'package:kossotrik/pages/settings_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fixtures.dart';

/// Menjawab kedua endpoint master; daftarnya bisa dibuat kosong dan
/// penyimpanannya bisa dibuat ditolak.
class _Stub extends Interceptor {
  _Stub({this.empty = false, this.rejectSave = false});

  final bool empty;
  final bool rejectSave;
  final List<RequestOptions> requests = [];

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.path == path).toList();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (rejectSave && options.path == '/master/set-chargerbox-evtap') {
      handler.reject(
        DioException.badResponse(
          statusCode: 400,
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 400,
            data: {
              'responseCode': '13',
              'responseMessage': 'Charge box ditolak CSMS',
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
        data: switch (options.path) {
          '/master/list-chargerbox' => masterListResponse(
            chargeBoxes: empty ? [] : null,
          ),
          _ => okResponse,
        },
      ),
    );
  }
}

Future<_Stub> _openSettings(
  WidgetTester tester, {
  bool empty = false,
  bool rejectSave = false,
}) async {
  // Layar kios tinggi; ukuran bawaan test terlalu pendek untuk dua
  // kartu yang isian kredensialnya terbuka.
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final stub = _Stub(empty: empty, rejectSave: rejectSave);
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(theme: AppTheme.build(), home: const SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();

  return stub;
}

/// Mengetik kode lalu menekan "Kirim" pada modal Kode SPKLU.
Future<void> _sendCode(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(SettingsPage.spkluCodeKey));
  await tester.pumpAndSettle();
  expect(find.text('Kode SPKLU'), findsOneWidget);

  await tester.enterText(find.byType(TextField).first, code);
  await tester.tap(find.text('Kirim'));
  await tester.pumpAndSettle();
}

/// Mencentang kartu charge box ke-[index].
Future<void> _check(WidgetTester tester, int index) async {
  await tester.tap(find.byType(Checkbox).at(index));
  await tester.pumpAndSettle();
}

/// Mengisi field berlabel [label] pada kartu yang sedang terbuka.
Future<void> _fill(WidgetTester tester, String label, String value) async {
  await tester.enterText(
    find.ancestor(of: find.text(label), matching: find.byType(TextField)).first,
    value,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kode SPKLU dikirim ke /master/list-chargerbox', (tester) async {
    final stub = await _openSettings(tester);

    await _sendCode(tester, 'SPKLU-SMR');

    final request = stub.to('/master/list-chargerbox').single;
    expect(request.method, 'POST');
    expect(request.data, {'idSpklu': 'SPKLU-SMR'});
    expect(find.byType(MasterChargeBoxPage), findsOneWidget);
    expect(find.text('CB-SMR-01 • Kempower • 200 kW • 1 konektor'), findsOne);
  });

  /// Kode yang tidak mengembalikan apa pun kemungkinan salah ketik,
  /// jadi modalnya tetap terbuka untuk diperbaiki di tempat.
  testWidgets('daftar kosong tidak membuka halaman', (tester) async {
    await _openSettings(tester, empty: true);

    await _sendCode(tester, 'SPKLU-XXX');

    expect(find.byType(MasterChargeBoxPage), findsNothing);
    expect(find.text('Tidak ada charge box untuk kode itu.'), findsOneWidget);
  });

  group('menyimpan charge box yang dicentang', () {
    testWidgets('satu permintaan untuk tiap yang dicentang', (tester) async {
      final stub = await _openSettings(tester);
      await _sendCode(tester, 'SPKLU-SMR');

      await _check(tester, 0);
      await _fill(tester, 'ID Edge Controller', 'EC-00001-1');
      await _fill(tester, 'Password', 'station-dev-only');
      await _check(tester, 1);

      // Kartu kedua ikut diisi; keduanya punya isian sendiri.
      await tester.enterText(
        find
            .ancestor(
              of: find.text('Password'),
              matching: find.byType(TextField),
            )
            .last,
        'kedua-rahasia',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simpan Info Charge Box'));
      await tester.pumpAndSettle();

      final saves = stub.to('/master/set-chargerbox-evtap');
      expect(saves, hasLength(2));
      expect(saves.first.data, {
        'idEdgeController': 'EC-00001-1',
        'idSpklu': 'SPKLU-SMR',
        'chargerBoxId': 'CB-SMR-01',
        'authType': 'BASIC_AUTH',
        // Username ikut id charge boxnya kecuali diganti petugas.
        'username': 'CB-SMR-01',
        'password': 'station-dev-only',
      });
      expect((saves.last.data as Map)['chargerBoxId'], 'CB-SMR-02');
      expect(find.text('Tersimpan'), findsNWidgets(2));
    });

    testWidgets('yang tidak dicentang tidak ikut terkirim', (tester) async {
      final stub = await _openSettings(tester);
      await _sendCode(tester, 'SPKLU-SMR');

      await _check(tester, 1);
      await _fill(tester, 'Password', 'rahasia');
      await tester.tap(find.text('Simpan Info Charge Box'));
      await tester.pumpAndSettle();

      final saves = stub.to('/master/set-chargerbox-evtap');
      expect(saves, hasLength(1));
      expect((saves.single.data as Map)['chargerBoxId'], 'CB-SMR-02');
    });

    /// Backend menolak username/password kosong untuk auth selain NONE,
    /// jadi dihentikan di sini supaya tidak ada yang terkirim separuh.
    testWidgets('tanpa password tidak mengirim apa pun', (tester) async {
      final stub = await _openSettings(tester);
      await _sendCode(tester, 'SPKLU-SMR');

      await _check(tester, 0);
      await tester.tap(find.text('Simpan Info Charge Box'));
      await tester.pumpAndSettle();

      expect(stub.to('/master/set-chargerbox-evtap'), isEmpty);
      expect(find.text('Username dan password wajib diisi.'), findsOneWidget);
    });

    testWidgets('NONE dikirim tanpa kredensial', (tester) async {
      final stub = await _openSettings(tester);
      await _sendCode(tester, 'SPKLU-SMR');

      await _check(tester, 0);
      await tester.tap(find.text('Basic Auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tanpa Autentikasi').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simpan Info Charge Box'));
      await tester.pumpAndSettle();

      final save = stub.to('/master/set-chargerbox-evtap').single;
      expect((save.data as Map).containsKey('username'), isFalse);
      expect((save.data as Map)['authType'], 'NONE');
    });

    testWidgets('penolakan backend ditampilkan pada kartunya', (tester) async {
      await _openSettings(tester, rejectSave: true);
      await _sendCode(tester, 'SPKLU-SMR');

      await _check(tester, 0);
      await _fill(tester, 'Password', 'rahasia');
      await tester.tap(find.text('Simpan Info Charge Box'));
      await tester.pumpAndSettle();

      expect(find.text('Gagal'), findsOneWidget);
      expect(find.text('Charge box ditolak CSMS'), findsOneWidget);
    });
  });
}
