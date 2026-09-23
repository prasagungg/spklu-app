import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/models/reservation.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';
import 'flow_helpers.dart';

/// Merekam setiap request dan menjawabnya; booking bisa dibuat ditolak.
class _Recorder extends Interceptor {
  _Recorder({this.bookingAccepted = true});

  final bool bookingAccepted;
  final List<RequestOptions> requests = [];

  /// Setelah perintah start, konektornya melapor sedang mengisi —
  /// seperti backend sungguhan.
  bool _charging = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    if (options.path == '/transaction/charging/start') _charging = true;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: switch (options.path) {
          '/list-chargerbox' => listResponse([
              chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01'),
            ]),
          '/detail-chargerbox' => chargeBoxDetailResponse(
              connectors: [connectorJson(status: _charging ? 3 : 1)],
            ),
          '/booked-connector' => bookingResponse(accepted: bookingAccepted),
          '/manage-sessioncode' => sessionCodeResponse(),
          '/cancelled-connector' => cancellationResponse(),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/transaction/payment-billing' => paymentBillingResponse(),
          '/transaction/charging/ongoing-kwh' => ongoingKwhResponse(
              status: 3,
            ),
          _ => okResponse,
        },
      ),
    );
  }

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.path == path).toList();

  /// Berapa kali konektor dipesan. Memanggilnya lagi bukan menaikkan
  /// tahap, melainkan membuat pemesanan baru.
  int get bookings => to('/booked-connector').length;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Membuka daftar konektor lalu menekan Gun 1.
Future<void> _pickConnector(WidgetTester tester, _Recorder recorder) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
  );

  await tester.pumpWidget(
    SPKLUApp(repository: repo, cardReader: FakeCardReader()),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('01'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gun 1'));
  await settleFrames(tester);
}

void main() {
  group('R0 saat konektor dipilih', () {
    testWidgets('mengunci konektor lalu masuk ke Pilih Nominal',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);

      await passSessionCode(tester);

      final booking = recorder.requests
          .firstWhere((r) => r.path == '/booked-connector');
      expect(booking.method, 'POST');
      expect(booking.data, {
        'chargeBoxId': 'CB-SMR-01',
        // Backend memakai teks untuk nomor konektor.
        'connectorId': '1',
      });
      expect(find.text('Pilih Nominal'), findsOneWidget);
    });

    /// Inti dari booking: begitu konektornya tidak bersedia, pengguna
    /// tidak boleh menghabiskan waktu memilih nominal dan membayar.
    testWidgets('konektor yang tidak bersedia menghentikan alur',
        (tester) async {
      final recorder = _Recorder(bookingAccepted: false);
      await _pickConnector(tester, recorder);

      expect(find.text('Pilih Nominal'), findsNothing);
      expect(find.byType(ChargeBoxPage), findsOneWidget);
      expect(
        find.textContaining('baru saja diambil pengguna lain'),
        findsOneWidget,
      );
    });

    testWidgets('penolakan memuat ulang daftar karena sudah basi',
        (tester) async {
      final recorder = _Recorder(bookingAccepted: false);
      await _pickConnector(tester, recorder);

      expect(
        recorder.requests.where((r) => r.path == '/list-chargerbox').length,
        greaterThan(1),
      );
    });
  });

  /// Tahap dinaikkan backend sendiri; aplikasi memesan sekali saja.
  /// Memanggil `booked-connector` lagi akan membuat pemesanan baru,
  /// bukan menaikkan tahap.
  testWidgets('konektor dipesan sekali saja sepanjang alur',
      (tester) async {
    final recorder = _Recorder();
    await _pickConnector(tester, recorder);
    expect(recorder.bookings, 1);

    await passSessionCode(tester);

    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();

    // Ordernya menempel pada pemesanan itu.
    final order = recorder.to('/transaction/push-order').single;
    expect((order.data as Map)['reservationId'], 'RESV-1');


    await tester.tap(find.text('Konfirmasi & Bayar'));
    await _settle(tester);

    final reader = tester
        .widget<SPKLUApp>(find.byType(SPKLUApp))
        .cardReader as FakeCardReader;
    reader.tap();
    await _settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));


    await tester.tap(find.text('Mulai Pengisian'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian').last);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(recorder.bookings, 1, reason: 'tidak ada pemesanan tambahan');
    expect(find.text('Pengisian Dimulai'), findsOneWidget);
  });

  group('pembatalan saat alur ditinggalkan', () {
    testWidgets('keluar dari alur pembelian melepas konektor',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);
      await passSessionCode(tester);
      expect(find.text('Pilih Nominal'), findsOneWidget);
      expect(recorder.to('/cancelled-connector'), isEmpty);

      // Kembali dari Pilih Nominal hanya mundur satu langkah, ke kode
      // sesinya: pemesanannya masih dipegang pengguna ini.
      await tester.tap(find.text('Kembali'));
      await settleFrames(tester);
      expect(find.text('Kode Sesi'), findsOneWidget);
      expect(recorder.to('/cancelled-connector'), isEmpty);

      // Yang melepasnya adalah keluar dari alurnya sama sekali.
      await tester.tap(find.text('Batalkan Transaksi'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih Charge Box'), findsOneWidget);

      final cancel = recorder.to('/cancelled-connector').single;
      expect(cancel.method, 'POST');
      expect(cancel.data, {
        'chargeBoxId': 'CB-SMR-01',
        'connectorId': '1',
        // Pemesanan yang dibatalkan, bukan tahapnya.
        'reservationId': 'RESV-1',
      });
    });

    testWidgets('tombol Home di tengah pembelian juga melepas',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);
      await passSessionCode(tester);

      // Tidak ada pilihan yang tercentang sejak awal.
      await tester.tap(find.text('10,0 kWh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);

      await tester.tap(find.byType(HomeButton).last);
      await tester.pumpAndSettle();

      final cancel = recorder.to('/cancelled-connector').single;
      expect((cancel.data as Map)['reservationId'], 'RESV-1');
      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    /// Begitu pengisian jalan, konektornya sedang dipakai — bukan
    /// sekadar dipesan — jadi pulang ke daftar tidak boleh melepasnya.
    testWidgets('pengisian yang sudah dimulai tidak ikut dibatalkan',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);
      await passSessionCode(tester);

      // Tidak ada pilihan yang tercentang sejak awal.
      await tester.tap(find.text('10,0 kWh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Konfirmasi & Bayar'));
      await _settle(tester);

      final reader = tester
          .widget<SPKLUApp>(find.byType(SPKLUApp))
          .cardReader as FakeCardReader;
      reader.tap();
      await _settle(tester);
      // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Mulai Pengisian'));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.tap(find.text('Mulai Pengisian').last);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Pengisian Dimulai'), findsOneWidget);

      await tester.tap(find.text('Kembali ke Halaman Awal'));
      await tester.pumpAndSettle();

      expect(find.text('Pilih Charge Box'), findsOneWidget);
      expect(recorder.to('/cancelled-connector'), isEmpty);
    });

    testWidgets('menutup daftar konektor tanpa memilih tidak melepas apa pun',
        (tester) async {
      final recorder = _Recorder();
      final repo = ChargePointRepository(
        client: ApiClient.withDio(Dio()..interceptors.add(recorder)),
      );

      await tester.pumpWidget(SPKLUApp(repository: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();
      expect(find.text('Daftar Konektor'), findsOneWidget);

      // Ditutup lewat tombol silang, tanpa memilih konektor.
      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();

      expect(recorder.to('/cancelled-connector'), isEmpty);
      expect(recorder.to('/booked-connector'), isEmpty);
    });
  });

  testWidgets('kode sesi dan referensi datang dari order', (tester) async {
    final recorder = _Recorder();
    await _pickConnector(tester, recorder);
    await passSessionCode(tester);

    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await _settle(tester);

    final reader = tester
        .widget<SPKLUApp>(find.byType(SPKLUApp))
        .cardReader as FakeCardReader;
    reader.tap();
    await _settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    // Keduanya dulu dikarang aplikasi; sekarang dari push-order.
    expect(find.text('Pembayaran Berhasil'), findsOneWidget);
    expect(find.text('29'), findsOneWidget);
    await tester.tap(find.text('Detail Transaksi'));
    await tester.pumpAndSettle();
    expect(find.text('81067'), findsOneWidget);
  });

  /// Kode sesi ada supaya pengguna bisa kembali ke sesinya sendiri;
  /// kalau kodenya tidak membuka apa-apa, layar itu tidak ada gunanya.
  testWidgets('kode sesi membuka kembali sesi yang sedang mengisi',
      (tester) async {
    final recorder = _Recorder();
    await _pickConnector(tester, recorder);
    await passSessionCode(tester);

    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await _settle(tester);

    final reader = tester
        .widget<SPKLUApp>(find.byType(SPKLUApp))
        .cardReader as FakeCardReader;
    reader.tap();
    await _settle(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Mulai Pengisian'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian').last);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    await reopenChargingSession(tester);

    // Kodenya diperiksa backend, bukan ditebak aplikasi. Endpoint yang
    // sama juga dipakai memantau nozzle, jadi yang diperiksa di sini
    // panggilan terakhir — yaitu verifikasinya.
    final check = recorder.to('/manage-sessioncode').last;
    expect(check.data, {
      'chargeBoxId': 'CB-SMR-01',
      'connectorId': '1',
      'sessionCode': '29',
    });
    expect(find.text('Sedang Mengisi'), findsOneWidget);

    // Pemantauan memakai order dari hasil verifikasi itu — bukan
    // ingatan lokal, sehingga sesi dari unit lain pun bisa dibuka.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final polls = recorder.to('/transaction/charging/ongoing-kwh');
    expect(polls, isNotEmpty);
    expect(polls.last.data, {'orderId': 'YZ00ZG5SP9HUNVRPTZH69Y7POW'});
  });

  group('Reservation', () {
    test('diurai dari payload nyata', () {
      final r = Reservation.fromJson(const {
        'chargeBoxId': 'CB-SMR-01',
        'chargeboxName': 'Kempower Satellite 200 kW',
        'connectorName': 'Gun 1',
        'connectorId': '1',
        'connectorStatus': 'R0',
        'sessionExpired': '2026-09-23T09:56:04Z',
        'reservationId': 'U33tiFAl0Yj5TkCQyoUmU',
        'sessionCode': '05',
        'status': true,
      });

      expect(r.accepted, isTrue);
      expect(r.reservationId, 'U33tiFAl0Yj5TkCQyoUmU');
      expect(r.sessionCode, '05');
      // Tahapnya ditetapkan backend, bukan dikirim aplikasi.
      expect(r.connectorStatus, 'R0');
      expect(r.expiredAt, isNotNull);
    });

    test('data yang hilang tidak dianggap bersedia', () {
      expect(Reservation.fromJson(null).accepted, isFalse);
      expect(Reservation.fromJson(const {}).accepted, isFalse);
    });
  });
}