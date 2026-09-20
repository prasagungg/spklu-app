import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/pages/api_log_page.dart';
import 'package:kossotrik/services/api_log_store.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

import 'fixtures.dart';

/// Menjawab request di lapisan adapter, bukan interceptor.
///
/// Interceptor yang memanggil `handler.resolve()` melompati sisa
/// rantai, sehingga perekam tidak pernah melihat jawabannya. Mengganti
/// adapter membuat seluruh rantai berjalan persis seperti di produksi.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.fail = false, this.body});

  final bool fail;
  final Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Tidak dapat terhubung',
      );
    }

    return ResponseBody.fromString(
      jsonEncode(body ?? listResponse()),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(ApiLogStore store, {bool fail = false, Map<String, dynamic>? body}) {
  return Dio(BaseOptions(baseUrl: 'http://contoh.test/api'))
    ..interceptors.add(ApiLogRecorder(store: store))
    // Transformer bawaan Dio menguraikan JSON di isolate lain lewat
    // compute(), dan itu tidak pernah selesai di zona async palsu milik
    // widget test. Versi sinkron menguraikannya di tempat.
    ..transformer = SyncTransformer()
    ..httpClientAdapter = _Adapter(fail: fail, body: body);
}

/// Menembak satu request dari dalam widget test.
///
/// Harus lewat [WidgetTester.runAsync]: di zona async palsu milik
/// widget test, Future milik Dio tidak pernah selesai.
Future<void> _call(
  WidgetTester tester,
  ApiLogStore store, {
  String path = '/list-chargerbox',
  Object? body,
}) async {
  await tester.runAsync(
    () => _dio(store).post<Map<String, dynamic>>(path, data: body),
  );
}

void main() {
  group('perekam', () {
    test('mencatat method, path, dan body yang dikirim', () async {
      final store = ApiLogStore();

      await _dio(store).post<Map<String, dynamic>>(
        '/list-chargerbox',
        data: '{"idSpklu":"SPKLU-SMR"}',
      );

      final entry = store.entries.single;
      expect(entry.method, 'POST');
      expect(entry.path, '/list-chargerbox');
      expect(entry.title, 'POST /list-chargerbox');
      expect(entry.requestBody, '{"idSpklu":"SPKLU-SMR"}');
      expect(entry.url, 'http://contoh.test/api/list-chargerbox');
    });

    test('melengkapi entri dengan status dan kode amplop', () async {
      final store = ApiLogStore();

      await _dio(store).post<Map<String, dynamic>>('/list-chargerbox');

      final entry = store.entries.single;
      expect(entry.statusCode, 200);
      expect(entry.responseCode, '00');
      expect(entry.responseMessage, 'Success');
      expect(entry.isPending, isFalse);
      expect(entry.isFailure, isFalse);
      expect(entry.responseBody, contains('SPKLU-SMR'));
    });

    test('kegagalan jaringan tercatat sebagai error', () async {
      final store = ApiLogStore();

      await expectLater(
        _dio(store, fail: true).get<Map<String, dynamic>>('/progress'),
        throwsA(isA<DioException>()),
      );

      final entry = store.entries.single;
      expect(entry.error, 'Tidak dapat terhubung');
      expect(entry.isFailure, isTrue);
      expect(entry.statusCode, isNull);
      expect(entry.statusLabel, '—');
    });

    /// Backend membalas 200 dengan `responseCode` selain "00" — mudah
    /// terlewat kalau hanya status HTTP yang dilihat.
    test('amplop yang bukan 00 dihitung gagal walau HTTP 200', () async {
      final store = ApiLogStore();

      await _dio(
        store,
        body: const {'responseCode': '31', 'responseMessage': 'Not connected'},
      ).post<Map<String, dynamic>>('/start');

      final entry = store.entries.single;
      expect(entry.statusCode, 200);
      expect(entry.responseCode, '31');
      expect(entry.isFailure, isTrue);
    });

    test('query ikut masuk ke alamat yang ditampilkan', () async {
      final store = ApiLogStore();

      await _dio(store).get<Map<String, dynamic>>(
        '/progress',
        queryParameters: {'chargePointId': 'CB-SMR-01', 'connectorId': 1},
      );

      expect(
        store.entries.single.url,
        'http://contoh.test/api/progress'
        '?chargePointId=CB-SMR-01&connectorId=1',
      );
    });

    test('teks salinan memuat alamat, header, dan isi', () async {
      final store = ApiLogStore();

      await _dio(store).post<Map<String, dynamic>>(
        '/start',
        data: '{"chargePointId":"CB-SMR-01"}',
        options: Options(headers: {'client-id': 'edge'}),
      );

      final text = store.entries.single.toShareableText();
      expect(text, contains('POST http://contoh.test/api/start'));
      expect(text, contains('client-id: edge'));
      expect(text, contains('{"chargePointId":"CB-SMR-01"}'));
      expect(text, contains('Success'));
    });
  });

  group('riwayat', () {
    test('terbaru di atas', () async {
      final store = ApiLogStore();
      final dio = _dio(store);

      await dio.post<Map<String, dynamic>>('/pertama');
      await dio.post<Map<String, dynamic>>('/kedua');

      expect(store.entries.map((e) => e.path), ['/kedua', '/pertama']);
    });

    test('hanya menyimpan sebanyak kapasitasnya', () async {
      final store = ApiLogStore(capacity: 3);
      final dio = _dio(store);

      for (var i = 0; i < 5; i++) {
        await dio.post<Map<String, dynamic>>('/ke-$i');
      }

      expect(store.entries, hasLength(3));
      expect(store.entries.map((e) => e.path), ['/ke-4', '/ke-3', '/ke-2']);
    });

    test('bisa dikosongkan', () async {
      final store = ApiLogStore();
      await _dio(store).post<Map<String, dynamic>>('/list-chargerbox');

      store.clear();

      expect(store.isEmpty, isTrue);
    });
  });

  group('halaman', () {
    testWidgets('riwayat kosong menjelaskan dirinya', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: ApiLogPage(store: ApiLogStore())),
      );

      expect(find.textContaining('Belum ada panggilan'), findsOneWidget);
    });

    testWidgets('panggilan tampil dan detailnya bisa dibuka', (tester) async {
      final store = ApiLogStore();
      await _call(tester, store, body: '{"idSpklu":"SPKLU-SMR"}');

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: ApiLogPage(store: store)),
      );
      await tester.pumpAndSettle();

      expect(find.text('POST /list-chargerbox'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);

      await tester.tap(find.text('POST /list-chargerbox'));
      await tester.pumpAndSettle();

      expect(find.text('ALAMAT'), findsOneWidget);
      expect(find.text('REQUEST'), findsOneWidget);
      expect(find.text('RESPONSE'), findsOneWidget);
      expect(find.textContaining('{"idSpklu":"SPKLU-SMR"}'), findsOneWidget);
    });

    testWidgets('daftar ikut berubah saat panggilan baru masuk',
        (tester) async {
      final store = ApiLogStore();

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: ApiLogPage(store: store)),
      );
      expect(find.textContaining('Belum ada panggilan'), findsOneWidget);

      await _call(tester, store);
      await tester.pumpAndSettle();

      expect(find.text('POST /list-chargerbox'), findsOneWidget);
    });

    testWidgets('penyaring menyembunyikan yang tidak cocok', (tester) async {
      final store = ApiLogStore();
      await _call(tester, store, path: '/list-chargerbox');
      await _call(tester, store, path: '/status-konektor');

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: ApiLogPage(store: store)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));

      await tester.enterText(find.byKey(ApiLogPage.filterKey), 'status');
      await tester.pumpAndSettle();

      expect(find.text('POST /status-konektor'), findsOneWidget);
      expect(find.text('POST /list-chargerbox'), findsNothing);
    });

    testWidgets('penyaring tanpa hasil menjelaskan dirinya', (tester) async {
      final store = ApiLogStore();
      await _call(tester, store);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: ApiLogPage(store: store)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(ApiLogPage.filterKey), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('Tidak ada yang cocok dengan penyaring.'),
          findsOneWidget);
    });

    testWidgets('tombol hapus mengosongkan daftar', (tester) async {
      final store = ApiLogStore();
      await _call(tester, store);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.build(), home: ApiLogPage(store: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.textContaining('Belum ada panggilan'), findsOneWidget);
    });
  });

  testWidgets('tekan lama logo membuka inspektur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const PageScaffold(title: 'Uji', child: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(PageScaffold.logKey));
    await tester.pumpAndSettle();

    expect(find.text('Log API'), findsOneWidget);
  });
}
