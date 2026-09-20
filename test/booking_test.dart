import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/models/booking.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';

/// Merekam setiap request dan menjawabnya; booking bisa dibuat ditolak.
class _Recorder extends Interceptor {
  _Recorder({this.bookingAccepted = true});

  final bool bookingAccepted;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: switch (options.path) {
          '/list-chargerbox' => listResponse([
              chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01'),
            ]),
          '/status-konektor' => connectorStatusResponse(),
          '/booked-connector' => bookingResponse(accepted: bookingAccepted),
          '/cancelled-connector' => cancellationResponse(),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/progress' => progressResponse(),
          _ => okResponse,
        },
      ),
    );
  }

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.path == path).toList();

  /// Tahap booking yang terkirim, berurutan.
  List<String> get stages => [
        for (final r in requests)
          if (r.path == '/booked-connector')
            (r.data as Map)['connectorStatus'] as String,
      ];
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
  await tester.pumpAndSettle();
}

void main() {
  group('R0 saat konektor dipilih', () {
    testWidgets('mengunci konektor lalu masuk ke Pilih Nominal',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);

      final booking = recorder.requests
          .firstWhere((r) => r.path == '/booked-connector');
      expect(booking.method, 'POST');
      expect(booking.data, {
        'chargeBoxId': 'CB-SMR-01',
        // Backend memakai teks untuk nomor konektor.
        'connectorId': '1',
        'connectorStatus': 'R0',
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

  testWidgets('tahapnya naik mengikuti alur pembelian', (tester) async {
    final recorder = _Recorder();
    await _pickConnector(tester, recorder);
    expect(recorder.stages, ['R0']);

    // R1 — order dibuat.
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    expect(recorder.stages, ['R0', 'R1']);

    // R2 — pembayaran dikonfirmasi lewat tap kartu.
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
    expect(recorder.stages, ['R0', 'R1', 'R2']);

    // R3 — pengisian dimulai.
    await tester.tap(find.text('Mulai Pengisian'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian').last);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(recorder.stages, ['R0', 'R1', 'R2', 'R3']);
    expect(find.text('Sedang Mengisi'), findsOneWidget);
  });

  group('pembatalan saat alur ditinggalkan', () {
    testWidgets('kembali dari Pilih Nominal melepas konektor',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);
      expect(find.text('Pilih Nominal'), findsOneWidget);
      expect(recorder.to('/cancelled-connector'), isEmpty);

      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();

      final cancel = recorder.to('/cancelled-connector').single;
      expect(cancel.method, 'POST');
      expect(cancel.data, {
        'chargeBoxId': 'CB-SMR-01',
        'connectorId': '1',
        // Tahap terakhir yang sempat dilaporkan.
        'connectorStatus': 'R0',
      });
    });

    testWidgets('tombol Home di tengah pembelian juga melepas',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);

      // Tidak ada pilihan yang tercentang sejak awal.
      await tester.tap(find.text('10,0 kWh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);

      await tester.tap(find.byType(HomeButton).last);
      await tester.pumpAndSettle();

      final cancel = recorder.to('/cancelled-connector').single;
      // Tahapnya sudah naik ke R1 sebelum ditinggalkan.
      expect((cancel.data as Map)['connectorStatus'], 'R1');
      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    /// Begitu pengisian jalan, konektornya sedang dipakai — bukan
    /// sekadar dipesan — jadi pulang ke daftar tidak boleh melepasnya.
    testWidgets('pengisian yang sudah dimulai tidak ikut dibatalkan',
        (tester) async {
      final recorder = _Recorder();
      await _pickConnector(tester, recorder);

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
      expect(find.text('Sedang Mengisi'), findsOneWidget);

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

  group('BookingStage', () {
    test('kodenya sesuai kosakata backend', () {
      expect(BookingStage.selected.code, 'R0');
      expect(BookingStage.ordering.code, 'R1');
      expect(BookingStage.paid.code, 'R2');
      expect(BookingStage.starting.code, 'R3');
    });

    test('data yang hilang tidak dianggap bersedia', () {
      expect(BookingResult.fromJson(null).accepted, isFalse);
      expect(BookingResult.fromJson(const {}).accepted, isFalse);
    });
  });
}
