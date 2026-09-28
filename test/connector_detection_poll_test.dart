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
  /// membuat futurenya menggantung, supaya layar tunggu mode otomatis
  /// bisa diperiksa sebelum halamannya berpindah.
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
                  'responseCode': '14',
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

PrimaryButton _startButton(WidgetTester tester) => tester.widget<PrimaryButton>(
  find.widgetWithText(PrimaryButton, 'Mulai Pengisian'),
);

/// Satu putaran polling.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Melewati jeda mode otomatis, seberapa pun panjangnya.
Future<void> _passAutoPause(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 500));
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

  /// Selama charger masih melaporkan "Available", kabelnya belum
  /// terpasang dan perintah start tidak boleh bisa dikirim.
  testWidgets('tombol mati selama konektor masih Available', (tester) async {
    await _pump(tester);

    for (var i = 0; i < 5; i++) {
      await _tick(tester);
    }

    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(find.text('Menunggu konektor terdeteksi...'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
  });

  testWidgets('Preparing berarti nozzle sudah tercolok', (tester) async {
    final stub = await _pump(tester);

    await _tick(tester);
    expect(_startButton(tester).onPressed, isNull);

    // Kabel dicolokkan ke kendaraan.
    stub.status = 'Preparing';
    await _tick(tester);

    expect(find.text('Konektor Terhubung'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNotNull);
  });

  testWidgets('pemeriksaan berhenti setelah konektor terdeteksi', (
    tester,
  ) async {
    final stub = await _pump(tester, status: 'Preparing');

    await _tick(tester);
    final afterDetection = stub.checks.length;

    await _tick(tester);
    await _tick(tester);

    expect(stub.checks, hasLength(afterDetection));
  });

  /// Menebak status yang tidak dikenal sebagai "tercolok" akan
  /// mengirim perintah start yang pasti ditolak charger.
  testWidgets('status tak dikenal tidak dianggap tercolok', (tester) async {
    final stub = await _pump(tester);
    stub.status = 'SomethingElse';

    await _tick(tester);
    await _tick(tester);

    expect(tester.takeException(), isNull);
    expect(_startButton(tester).onPressed, isNull);
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

    await _passAutoPause(tester);

    expect(stub.starts, hasLength(1));
  });

  /// Charger yang rusak tidak akan pernah melaporkan "Preparing".
  /// Menyuruh pengguna menunggu di situ hanya membuang waktunya.
  testWidgets('konektor bermasalah dikatakan apa adanya', (tester) async {
    await _pump(tester, status: 'Faulted');

    await _tick(tester);

    expect(find.textContaining('tidak bisa dipakai (Faulted)'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
  });

  group('kabel yang sudah terpasang sejak halaman dibuka', () {
    /// Menyuruh memasang kabel yang sudah terpasang hanya membuat orang
    /// berdiri di depan tombol yang tidak ada gunanya ditekan.
    /// Jeda terpendeknya satu detik, jadi setengah detik pertama masih
    /// pasti berada di dalamnya.
    testWidgets('menahan diri dulu dan mengabarkan konektornya', (
      tester,
    ) async {
      final stub = await _pump(tester, status: 'Preparing');

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(
        find.textContaining('Pengisian akan dimulai otomatis'),
        findsOneWidget,
      );
      expect(stub.starts, isEmpty, reason: '/start menunggu jedanya habis');
      // Tidak ada yang perlu ditekan, termasuk Bantuan — yang di sini
      // hanya menawarkan pertolongan untuk masalah yang tidak ada.
      expect(
        find.widgetWithText(PrimaryButton, 'Mulai Pengisian'),
        findsNothing,
      );
      expect(find.text('Bantuan'), findsNothing);
    });

    testWidgets('memulai pengisian sendiri, tanpa tombol', (tester) async {
      final stub = await _pump(
        tester,
        status: 'Preparing',
        startOutcome: _Start.hang,
      );

      await _passAutoPause(tester);

      expect(stub.starts, hasLength(1), reason: '/start harus berangkat');
      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(find.text('Memulai pengisian…'), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryButton, 'Mulai Pengisian'),
        findsNothing,
      );
    });

    testWidgets('lanjut ke Pengisian Dimulai tanpa ditekan', (tester) async {
      await _pump(tester, status: 'Preparing');

      await pumpUntil(tester, find.text('Pengisian Dimulai'));
    });

    /// Mode otomatis tidak punya tombol. Kegagalan yang tidak
    /// mengembalikan tombolnya akan menahan pengguna di layar tunggu
    /// yang tidak akan pernah selesai.
    testWidgets('start yang gagal memunculkan tombolnya kembali', (
      tester,
    ) async {
      await _pump(tester, status: 'Preparing', startOutcome: _Start.reject);

      await _passAutoPause(tester);

      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(find.text('Memulai pengisian…'), findsNothing);
      expect(_startButton(tester).onPressed, isNotNull);
      expect(find.text('Bantuan'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    /// Kabel yang dicolokkan *sambil* menunggu di halaman ini bukan
    /// urusan mode otomatis — pengguna yang menekan tombolnya.
    testWidgets('dicolok saat menunggu tetap menunggu tombol', (tester) async {
      final stub = await _pump(tester);

      await _tick(tester);
      stub.status = 'Preparing';
      await _tick(tester);

      expect(find.text('Konektor Terhubung'), findsOneWidget);
      expect(_startButton(tester).onPressed, isNotNull);
      expect(stub.starts, isEmpty, reason: '/start menunggu tombol ditekan');
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
