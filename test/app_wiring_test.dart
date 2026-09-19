import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

/// Merekam setiap request dan menjawabnya lewat [responder], sehingga
/// test bisa mengubah jawaban `/list` di tengah alur.
class _Recorder extends Interceptor {
  _Recorder(this.responder);

  final Map<String, dynamic> Function(String path) responder;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: responder(options.path),
        statusCode: 200,
      ),
    );
  }

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.path == path).toList();
}

/// Bentuk `/list` dengan status konektor 1 yang bisa diatur test.
///
/// Konektor 2 sengaja dibuat "Charging" supaya label "Tersedia" pada
/// bottom sheet hanya menunjuk satu konektor — kalau dua-duanya bebas,
/// tap-nya jadi ambigu dan bisa memilih konektor yang salah.
Map<String, dynamic> _list(String connector1Status) => {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePoints': [
          {
            'id': 'SIM-456',
            'vendor': 'Icon Digital',
            'model': 'OCPP Simulator',
            'connectors': [
              {'id': 1, 'status': connector1Status, 'errorCode': 'NoError'},
              {'id': 2, 'status': 'Charging', 'errorCode': 'NoError'},
            ],
          },
        ],
      },
    };

const _ok = {'responseCode': '00', 'responseMessage': 'Success'};

void main() {
  testWidgets('menekan Mulai Pengisian benar-benar mengirim POST /start',
      (tester) async {
    // Konektor 1 mulai "Available"; nanti diubah ke "Preparing" untuk
    // meniru kabel yang dicolokkan ke kendaraan.
    var connectorStatus = 'Available';
    final recorder = _Recorder(
      (path) => path == '/list' ? _list(connectorStatus) : _ok,
    );
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
    );

    await tester.pumpWidget(
      SPKLUApp(repository: repo, home: const ChargeBoxPage()),
    );
    await tester.pumpAndSettle();

    // Daftar charge box datang dari /list.
    expect(recorder.to('/list'), isNotEmpty);
    expect(find.text('SIM-456'), findsOneWidget);

    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();

    // Pilih konektor pertama yang tersedia.
    await tester.tap(find.text('Tersedia').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Bayar (Simulasi)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Tombol ini hanya berpindah halaman, belum menembak /start.
    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(recorder.to('/start'), isEmpty);

    // Selama konektor masih "Available", polling berjalan tapi tombol
    // tetap nonaktif dan /start tidak pernah terkirim.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(recorder.to('/start'), isEmpty);
    expect(
      recorder.to('/list').length,
      greaterThan(1),
      reason: 'halaman ini harus mem-polling /list',
    );

    // Kabel dicolokkan: charger melaporkan "Preparing".
    connectorStatus = 'Preparing';
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('Konektor Terhubung'), findsOneWidget);

    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final starts = recorder.to('/start');
    expect(starts, hasLength(1), reason: 'POST /start harus terkirim');
    expect(starts.single.method, 'POST');
    // targetKwh diambil dari nominal Rp50.000 yang terpilih (19,5 kWh).
    expect(starts.single.data, {
      'chargePointId': 'SIM-456',
      'connectorId': 1,
      'targetKwh': 19.5,
    });

    // Beri waktu transisi rute selesai sebelum memeriksa halaman status.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  testWidgets('halaman status mem-polling /progress dan pindah saat selesai',
      (tester) async {
    var connectorStatus = 'Available';
    var progressState = 'charging';
    var energyWh = 0;

    final recorder = _Recorder((path) {
      if (path == '/list') return _list(connectorStatus);
      if (path == '/progress') {
        return {
          'responseCode': '00',
          'responseMessage': 'Success',
          'data': {
            'chargePointId': 'SIM-456',
            'connectorId': 1,
            'transactionId': 7,
            'state': progressState,
            'connectorStatus': 'Charging',
            'percent': 50.0,
            'energyWh': energyWh,
            'powerW': progressState == 'finished' ? null : 12000,
            'durationSeconds': 30,
            'stopReason': progressState == 'finished' ? 'Remote' : null,
            'stoppedAt': progressState == 'finished'
                ? '2026-09-17T20:58:35.135618667+07:00'
                : null,
          },
        };
      }
      return _ok;
    });

    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
    );

    await tester.pumpWidget(
      SPKLUApp(repository: repo, home: const ChargeBoxPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bayar (Simulasi)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Kabel dicolokkan. Polling berjalan async, jadi perlu beberapa
    // pump agar futurenya sempat selesai.
    connectorStatus = 'Preparing';
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Konektor Terhubung'), findsOneWidget);

    await tester.tap(find.text('Mulai Pengisian').last);
    // POST /start async, lalu transisi rute.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sedang Mengisi'), findsOneWidget);

    // Energi naik mengikuti /progress.
    energyWh = 6400;
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('6,4 kWh'), findsOneWidget);
    expect(recorder.to('/progress'), isNotEmpty);
    expect(
      recorder.to('/progress').first.queryParameters,
      {'chargePointId': 'SIM-456', 'connectorId': 1},
    );

    // Charger berhenti sendiri: state jadi "finished".
    progressState = 'finished';
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pengisian Selesai'), findsOneWidget);
    expect(find.text('Energi Tersalur'), findsOneWidget);
  });

  testWidgets('Akhiri Pengisian mengirim /stop dengan connectorId',
      (tester) async {
    var connectorStatus = 'Available';
    final recorder = _Recorder((path) {
      if (path == '/list') return _list(connectorStatus);
      if (path == '/progress') {
        return {
          'responseCode': '00',
          'responseMessage': 'Success',
          'data': {
            'chargePointId': 'SIM-456',
            'connectorId': 1,
            'transactionId': 7,
            'state': 'charging',
            'connectorStatus': 'Charging',
            'percent': 50.0,
            'energyWh': 6400,
            'powerW': 12000,
            'durationSeconds': 30,
          },
        };
      }
      return _ok;
    });

    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
    );

    await tester.pumpWidget(
      SPKLUApp(repository: repo, home: const ChargeBoxPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bayar (Simulasi)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    connectorStatus = 'Preparing';
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Mulai Pengisian').last);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sedang Mengisi'), findsOneWidget);

    await tester.tap(find.text('Akhiri Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Akhiri Pengisian?'), findsOneWidget);

    await tester.tap(find.text('Ya, Akhiri Pengisian'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final stops = recorder.to('/stop');
    expect(stops, hasLength(1));
    expect(stops.single.data, {'chargePointId': 'SIM-456', 'connectorId': 1});

    // Setelah /stop, aplikasi membaca /progress sampai "finished"
    // sebelum menampilkan rincian akhir.
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Pengisian Selesai'), findsOneWidget);
  });
}
