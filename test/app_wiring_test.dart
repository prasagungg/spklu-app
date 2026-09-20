import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';

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

/// Bentuk `POST /list-chargerbox` dengan satu charge box dua konektor.
///
/// Konektor kedua sengaja dimatikan supaya hanya satu yang bisa
/// ditekan — kalau dua-duanya hidup, tap-nya jadi ambigu dan bisa
/// memilih konektor yang salah.
Map<String, dynamic> _list() => listResponse([
      chargeBoxJson(
        id: 'CB-SMR-01',
        nama: 'CB-SMR-01',
        connectors: [
          connectorJson(id: '1'),
          connectorJson(id: '2', nama: 'Gun 2', status: 0),
        ],
      ),
    ]);

const _ok = okResponse;

void main() {
  testWidgets('menekan Mulai Pengisian benar-benar mengirim POST /start',
      (tester) async {
    final recorder = _Recorder(
      (path) => switch (path) {
        '/list-chargerbox' => _list(),
        '/booked-connector' => bookingResponse(),
        '/list-kwh' => kwhOptionsResponse(),
        '/count-kwh' => countKwhResponse(),
        '/transaction/push-order' => pushOrderResponse(),
        '/transaction/inquiry-billing' => inquiryBillingResponse(),
        '/transaction/payment-billing' => paymentBillingResponse(),
        _ => _ok,
      },
    );
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
    );

    final reader = FakeCardReader();


    await tester.pumpWidget(
      SPKLUApp(repository: repo, cardReader: reader),
    );
    await tester.pumpAndSettle();

    // Daftar charge box datang dari POST /list-chargerbox.
    expect(recorder.to('/list-chargerbox'), isNotEmpty);
    expect(
      recorder.to('/list-chargerbox').single.data,
      {'idSpklu': Env.idSpklu},
    );
    expect(find.text('CB-SMR-01'), findsOneWidget);

    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();

    // Pilih konektor yang hidup.
    await tester.tap(find.text('Gun 1'));
    await tester.pumpAndSettle();

    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Kartu e-Money ditempelkan menggantikan tombol bayar.
    reader.tap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    // Tombol ini hanya berpindah halaman, belum menembak start.
    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(recorder.to('/transaction/charging/start'), isEmpty);

    // Sebelum jeda deteksi habis, tombolnya belum aktif dan perintah
    // start belum terkirim.
    expect(recorder.to('/transaction/charging/start'), isEmpty);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Konektor Terhubung'), findsOneWidget);

    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final starts = recorder.to('/transaction/charging/start');
    expect(starts, hasLength(1), reason: 'perintah start harus terkirim');
    expect(starts.single.method, 'POST');
    // Charge box, konektor, dan kWh-nya melekat pada order.
    expect(starts.single.data, {'orderId': 'YZ00ZG5SP9HUNVRPTZH69Y7POW'});

    // Beri waktu transisi rute selesai sebelum memeriksa halaman status.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  testWidgets('halaman status mem-polling /progress dan pindah saat selesai',
      (tester) async {
    var progressStatus = 3;
    var charged = 0.0;

    final recorder = _Recorder((path) {
      if (path == '/list-chargerbox') return _list();
      if (path == '/booked-connector') return bookingResponse();
      if (path == '/list-kwh') return kwhOptionsResponse();
      if (path == '/count-kwh') return countKwhResponse();
      if (path == '/transaction/push-order') return pushOrderResponse();
      if (path == '/transaction/inquiry-billing') {
        return inquiryBillingResponse();
      }
      if (path == '/transaction/payment-billing') {
        return paymentBillingResponse();
      }
      if (path == '/transaction/charging/ongoing-kwh') {
        return ongoingKwhResponse(
          orderId: 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
          status: progressStatus,
          charged: charged,
        );
      }
      return _ok;
    });

    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
    );

    final reader = FakeCardReader();


    await tester.pumpWidget(
      SPKLUApp(repository: repo, cardReader: reader),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await tester.pumpAndSettle();
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Kartu e-Money ditempelkan menggantikan tombol bayar.
    reader.tap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Jeda deteksi habis dan tombolnya aktif.
    await tester.pump(const Duration(seconds: 3));
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

    // Energi naik mengikuti ongoing-kwh.
    charged = 6.4;
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('6,4 kWh'), findsOneWidget);
    final polls = recorder.to('/transaction/charging/ongoing-kwh');
    expect(polls, isNotEmpty);
    expect(polls.first.data, {'orderId': 'YZ00ZG5SP9HUNVRPTZH69Y7POW'});

    // Charger berhenti sendiri: statusnya jadi selesai.
    progressStatus = 4;
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
    final recorder = _Recorder((path) {
      if (path == '/list-chargerbox') return _list();
      if (path == '/booked-connector') return bookingResponse();
      if (path == '/list-kwh') return kwhOptionsResponse();
      if (path == '/count-kwh') return countKwhResponse();
      if (path == '/transaction/push-order') return pushOrderResponse();
      if (path == '/transaction/inquiry-billing') {
        return inquiryBillingResponse();
      }
      if (path == '/transaction/payment-billing') {
        return paymentBillingResponse();
      }
      if (path == '/transaction/charging/ongoing-kwh') {
        return {
          'responseCode': '00',
          'responseMessage': 'Success',
          'data': {
            'chargePointId': 'CB-SMR-01',
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

    final reader = FakeCardReader();


    await tester.pumpWidget(
      SPKLUApp(repository: repo, cardReader: reader),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await tester.pumpAndSettle();
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Kartu e-Money ditempelkan menggantikan tombol bayar.
    reader.tap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Mulai Pengisian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pump(const Duration(seconds: 3));
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

    final stops = recorder.to('/transaction/charging/stop');
    expect(stops, hasLength(1));
    expect(stops.single.data, {'orderId': 'YZ00ZG5SP9HUNVRPTZH69Y7POW'});

    // Setelah stop, aplikasi membaca ongoing-kwh sampai selesai
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
