import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/connect_connector_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/primary_button.dart';
import 'package:kossotrik/widgets/session_widgets.dart';

import 'fixtures.dart';
import 'flow_helpers.dart';

/// Melaporkan status OCPP yang bisa diubah test di tengah jalan.
class _Stub extends Interceptor {
  _Stub(this.status, {this.startOutcome = _Start.ok});

  String status;

  /// Bagaimana `/transaction/charging/start` dijawab. [_Start.hang]
  /// membuat futurenya menggantung, supaya layar tunggunya bisa
  /// diperiksa sebelum halamannya berpindah.
  final _Start startOutcome;

  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (options.path == '/transaction/charging/start') {
      switch (startOutcome) {
        case _Start.hang:
          return;
        case _Start.reject:
          handler.reject(
            DioException.badResponse(
              statusCode: 400,
              requestOptions: options,
              response: Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 400,
                data: {
                  'responseCode': '31',
                  'responseMessage': 'Charge point offline',
                },
              ),
            ),
          );
          return;
        case _Start.ok:
          break;
      }
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path == '/check-status-connector'
            ? connectorStatusResponse(status: status)
            : okResponse,
      ),
    );
  }

  List<RequestOptions> get checks =>
      requests.where((r) => r.path == '/check-status-connector').toList();

  List<RequestOptions> get starts =>
      requests.where((r) => r.path == '/transaction/charging/start').toList();
}

/// Jawaban yang disiapkan untuk `/transaction/charging/start`.
enum _Start { ok, reject, hang }

ChargingSession _session() {
  final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

  return ChargingSession(
    chargeBox: box,
    connector: box.connectors.single,
    sessionCode: '29',
    reference: '81067',
    createdAt: DateTime(2026),
    orderId: 'ORDER-1',
  );
}

Future<_Stub> _pump(
  WidgetTester tester, {
  String status = 'Available',
  _Start startOutcome = _Start.ok,
}) async {
  final stub = _Stub(status, startOutcome: startOutcome);
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: ConnectConnectorPage(session: _session()),
      ),
    ),
  );
  await tester.pump();

  return stub;
}

/// Satu putaran polling.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Melewati satu jeda layar tunggu, seberapa pun panjangnya.
///
/// Jedanya dipatok `flutter_test_config`; enam putaran memberi margin di
/// atas patokan itu tanpa perlu mengetahui angkanya di sini.
Future<void> _passPause(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await _tick(tester);
  }
}

void main() {
  testWidgets('status konektor ditanyakan tiap detik', (tester) async {
    final stub = await _pump(tester);

    await _tick(tester);
    await _tick(tester);

    expect(stub.checks, hasLength(greaterThanOrEqualTo(2)));
    expect(stub.checks.first.data, {
      'chargeBoxId': 'CB-SMR-01',
      'connectorId': '1',
    });
  });

  group('menunggu kabel dipasang', () {
    /// Selama charger masih melaporkan "Available", kabelnya belum
    /// terpasang dan perintah start tidak boleh berangkat.
    testWidgets('layarnya tidak pindah ke mana-mana', (tester) async {
      final stub = await _pump(tester);

      await _passPause(tester);
      await _passPause(tester);

      expect(find.text('Hubungkan Konektor'), findsOneWidget);
      expect(find.text('Menunggu konektor terdeteksi...'), findsOneWidget);
      expect(stub.starts, isEmpty);
    });

    /// Di sinilah orang berdiri dengan kabel di tangan — satu-satunya
    /// tempat di halaman ini yang benar-benar memerlukan tombol.
    testWidgets('Bantuan ada selagi memasang, hilang setelah terhubung', (
      tester,
    ) async {
      final stub = await _pump(tester, startOutcome: _Start.hang);

      await _tick(tester);
      expect(find.text('Bantuan'), findsOneWidget);

      stub.status = 'Preparing';
      await _passPause(tester);

      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(find.text('Bantuan'), findsNothing);
    });

    /// Menebak status yang tidak dikenal sebagai "tercolok" akan
    /// mengirim perintah start yang pasti ditolak charger.
    testWidgets('status tak dikenal tidak dianggap tercolok', (tester) async {
      final stub = await _pump(tester);
      stub.status = 'SomethingElse';

      await _passPause(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Hubungkan Konektor'), findsOneWidget);
      expect(stub.starts, isEmpty);
    });

    /// Charger yang rusak tidak akan pernah melaporkan "Preparing".
    /// Menyuruh pengguna menunggu di situ hanya membuang waktunya.
    testWidgets('konektor bermasalah dikatakan apa adanya', (tester) async {
      final stub = await _pump(tester, status: 'Faulted');

      await _tick(tester);

      expect(
        find.textContaining('tidak bisa dipakai (Faulted)'),
        findsOneWidget,
      );
      expect(stub.starts, isEmpty);
    });
  });

  group('kabel terdeteksi', () {
    testWidgets('pemeriksaan berhenti setelah terdeteksi', (tester) async {
      final stub = await _pump(tester, status: 'Preparing');

      await _tick(tester);
      final afterDetection = stub.checks.length;

      await _tick(tester);
      await _tick(tester);

      expect(stub.checks, hasLength(afterDetection));
    });

    /// Charger bisa melewati "Preparing" bila sesinya sudah jalan; kalau
    /// keadaan sesudahnya tidak ikut dihitung, halamannya menggantung.
    testWidgets('status sesudah Preparing juga berarti kabelnya terpasang', (
      tester,
    ) async {
      final stub = await _pump(
        tester,
        status: 'SuspendedEV',
        startOutcome: _Start.hang,
      );

      await _passPause(tester);
      await _passPause(tester);

      expect(stub.starts, hasLength(1));
    });

    testWidgets('memulai pengisian sendiri, tanpa tombol', (tester) async {
      final stub = await _pump(
        tester,
        status: 'Preparing',
        startOutcome: _Start.hang,
      );

      await _passPause(tester);
      await _passPause(tester);

      expect(stub.starts, hasLength(1), reason: '/start harus berangkat');
      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(find.text('Memulai pengisian…'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
      expect(find.text('Bantuan'), findsNothing);
    });

    /// Perintahnya ditahan dulu supaya pengguna sempat membaca bahwa
    /// konektornya memang sudah terdeteksi.
    testWidgets('menahan diri dulu dan mengabarkan konektornya', (
      tester,
    ) async {
      final stub = await _pump(tester, status: 'Preparing');

      await _passPause(tester);

      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(
        find.textContaining('Pengisian akan dimulai otomatis'),
        findsOneWidget,
      );
      expect(stub.starts, isEmpty, reason: '/start menunggu jedanya habis');
    });

    testWidgets('lanjut ke Pengisian Dimulai tanpa ditekan', (tester) async {
      await _pump(tester, status: 'Preparing');

      await pumpUntil(tester, find.text('Pengisian Dimulai'));
    });
  });

  /// Kabel yang sudah terpasang sejak halaman dibuka tidak boleh membuat
  /// layar pertamanya berkelebat: yang tersisa di ingatan pengguna cuma
  /// aplikasi yang melompat sendiri tanpa penjelasan.
  group('Hubungkan Konektor tidak pernah dilewati', () {
    testWidgets('kabel yang sudah terpasang tetap melihat layar pertama', (
      tester,
    ) async {
      await _pump(tester, status: 'Preparing');

      await _tick(tester);

      expect(find.text('Hubungkan Konektor'), findsOneWidget);
      expect(find.text('Konektor Terhubung'), findsNothing);
    });

    testWidgets('yang dicolok belakangan menunggu jeda yang sama', (
      tester,
    ) async {
      final stub = await _pump(tester);

      stub.status = 'Preparing';
      await _tick(tester);

      expect(find.text('Hubungkan Konektor'), findsOneWidget);

      await _passPause(tester);

      expect(find.text('Konektor Terhubung'), findsOneWidget);
    });
  });

  group('start yang ditolak charger', () {
    /// Tanpa tombol alur normal, kegagalan harus memunculkan jalan
    /// keluarnya sendiri — kalau tidak pengguna tertahan di layar tunggu
    /// yang tidak akan pernah selesai.
    testWidgets('menawarkan Coba Lagi beserta alasannya', (tester) async {
      final stub = await _pump(
        tester,
        status: 'Preparing',
        startOutcome: _Start.reject,
      );

      await _passPause(tester);
      await _passPause(tester);

      expect(stub.starts, hasLength(1));
      expect(find.text('Coba Lagi'), findsOneWidget);
      expect(find.text('Bantuan'), findsOneWidget);
      expect(
        find.textContaining('tidak terhubung ke controller'),
        findsWidgets,
      );
    });

    /// Mengulanginya sendiri tiap beberapa detik hanya menghujani
    /// charger yang sedang bermasalah.
    testWidgets('tidak mencoba ulang sendiri', (tester) async {
      final stub = await _pump(
        tester,
        status: 'Preparing',
        startOutcome: _Start.reject,
      );

      await _passPause(tester);
      await _passPause(tester);
      await _passPause(tester);
      await _passPause(tester);

      expect(stub.starts, hasLength(1));
    });

    testWidgets('Coba Lagi mengirim ulang perintahnya', (tester) async {
      final stub = await _pump(
        tester,
        status: 'Preparing',
        startOutcome: _Start.reject,
      );

      await _passPause(tester);
      await _passPause(tester);

      await tester.tap(find.text('Coba Lagi'));
      await tester.pump();
      await _passPause(tester);

      expect(stub.starts, hasLength(2));
    });
  });

  testWidgets('hitung mundur dibaca dari sessionExpired tagihan', (
    tester,
  ) async {
    final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);
    final expiry = DateTime.now().add(const Duration(minutes: 8, seconds: 31));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ConnectConnectorPage(
          session: ChargingSession(
            chargeBox: box,
            connector: box.connectors.single,
            sessionCode: '29',
            reference: '81067',
            createdAt: DateTime(2026),
            orderId: 'ORDER-1',
            // Tenggat yang dikirim payment-billing, bukan sepuluh menit
            // tetap milik aplikasi.
            expiresAt: expiry,
          ),
        ),
      ),
    );
    await tester.pump();

    final pill = tester.widget<CountdownPill>(find.byType(CountdownPill));
    expect(pill.remaining.inSeconds, closeTo(511, 2));
  });
}
