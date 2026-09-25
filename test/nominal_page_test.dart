import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/pages/nominal_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/primary_button.dart';
import 'package:kossotrik/widgets/session_widgets.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub({
    this.options = const [10, 20, 30],
    this.failCount = false,
    this.orderErrorCode,
    this.rpTotal = 27135,
  });

  final List<num> options;
  final bool failCount;

  /// Total yang dibalas `/count-kwh`. Nol meniru konektor yang tarifnya
  /// belum diatur.
  final int rpTotal;

  /// Kode amplop yang dibalas `/transaction/push-order`, mis. "16".
  final String? orderErrorCode;

  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options_, RequestInterceptorHandler handler) {
    requests.add(options_);

    if (options_.path == '/count-kwh' && failCount) {
      handler.reject(
        DioException(
          requestOptions: options_,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }

    if (options_.path == '/transaction/push-order' && orderErrorCode != null) {
      handler.reject(
        DioException.badResponse(
          statusCode: 409,
          requestOptions: options_,
          response: Response<Map<String, dynamic>>(
            requestOptions: options_,
            statusCode: 409,
            data: {
              'responseCode': orderErrorCode,
              'responseMessage': 'Processing Another Request',
            },
          ),
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options_,
        statusCode: 200,
        data: switch (options_.path) {
          '/list-kwh' => kwhOptionsResponse(options),
          '/count-kwh' => countKwhResponse(
            kwh: (options_.data as Map)['kwh'] as num,
            rpTotal: rpTotal,
          ),
          '/transaction/push-order' => pushOrderResponse(
            kwh: (options_.data as Map)['kwh'] as num,
          ),
          _ => okResponse,
        },
      ),
    );
  }

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.path == path).toList();
}

final _box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

Future<_Stub> _pump(
  WidgetTester tester, {
  _Stub? stub,
  DateTime? expiresAt,
}) async {
  final it = stub ?? _Stub();
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(it)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: NominalPage(
          chargeBox: _box,
          connector: _box.connectors.single,
          expiresAt: expiresAt,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return it;
}

PrimaryButton _continueButton(WidgetTester tester) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Lanjutkan'));

void main() {
  /// Kartunya sempit — tiga per baris — jadi desainnya menulis
  /// angkanya saja, tanpa satuan.
  testWidgets('pilihan kWh diambil dari /list-kwh', (tester) async {
    final stub = await _pump(tester);

    expect(stub.to('/list-kwh'), hasLength(1));
    expect(find.text('10'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('10,0 kWh'), findsNothing);
  });

  /// Hitung mundurnya milik pemesanan, jadi sisa waktunya diteruskan
  /// dari halaman Kode Sesi — bukan sepuluh menit yang dimulai ulang.
  testWidgets('hitung mundur meneruskan batas waktu pemesanan', (tester) async {
    await _pump(
      tester,
      expiresAt: DateTime.now().add(const Duration(minutes: 5, seconds: 30)),
    );

    expect(find.byType(CompactCountdownPill), findsOneWidget);
    expect(find.textContaining('05:'), findsOneWidget);
  });

  /// Pilihan yang sudah tercentang sejak awal gampang terlewat, dan
  /// pengguna bisa membayar jumlah yang tidak pernah ia pilih sendiri.
  testWidgets('tidak ada yang terpilih saat halaman dibuka', (tester) async {
    final stub = await _pump(tester);

    expect(stub.to('/count-kwh'), isEmpty);
    expect(find.text('Rincian Harga'), findsNothing);
    expect(find.textContaining('Pilih jumlah kWh di atas'), findsOneWidget);
    expect(_continueButton(tester).onPressed, isNull);
  });

  testWidgets('memilih kWh menghitung harganya lewat /count-kwh', (
    tester,
  ) async {
    final stub = await _pump(tester);

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();

    final call = stub.to('/count-kwh').single;
    expect(call.method, 'POST');
    expect(call.data, {
      'chargeBoxId': 'CB-SMR-01',
      'connectorId': '1',
      'kwh': 20,
    });
  });

  testWidgets('rincian harga menampilkan angka dari backend', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    expect(find.text('Rincian Harga'), findsOneWidget);
    expect(find.text('Total kWh dibeli'), findsOneWidget);
    // Tarif pecahan dari backend, bukan hasil hitungan sendiri.
    expect(find.text('Rp2.466,78'), findsOneWidget);
    expect(find.text('Rp2.467'), findsOneWidget);
    expect(find.text('Rp27.135'), findsOneWidget);
    expect(_continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('biaya yang bernilai nol disembunyikan', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    // Semuanya nol pada payload ini; deretan "Rp0" hanya menenggelamkan
    // angka yang penting.
    expect(find.text('Biaya Admin'), findsNothing);
    expect(find.text('Bea Materai'), findsNothing);
    expect(find.text('Jaminan SPKLU'), findsNothing);
  });

  testWidgets('ganti pilihan menghitung ulang', (tester) async {
    final stub = await _pump(tester);

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();

    expect(stub.to('/count-kwh'), hasLength(2));
    expect((stub.to('/count-kwh').last.data as Map)['kwh'], 30);
  });

  /// Konektor yang tarifnya belum diatur dihargai Rp0 oleh backend.
  /// Ordernya boleh dibuat, tetapi tagihannya pasti ditolak saat
  /// membayar — jadi alurnya dihentikan sebelum kartu ditempelkan.
  testWidgets('total Rp0 menahan Lanjutkan dan menyebut sebabnya', (
    tester,
  ) async {
    await _pump(tester, stub: _Stub(rpTotal: 0));

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    expect(find.text('Rincian Harga'), findsOneWidget);
    // Catatannya ada di bawah rincian harga, di luar layar sejak
    // "Batalkan Transaksi" menambah tinggi bilah tombolnya.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Tarif konektor ini belum diatur'),
      findsOneWidget,
    );
    expect(_continueButton(tester).onPressed, isNull);
  });

  testWidgets('harga yang gagal dihitung tidak membuka Lanjutkan', (
    tester,
  ) async {
    await _pump(tester, stub: _Stub(failCount: true));

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    expect(find.text('Rincian Harga'), findsNothing);
    expect(_continueButton(tester).onPressed, isNull);
    expect(
      find.text('Tidak dapat terhubung ke server. Periksa jaringan Anda.'),
      findsOneWidget,
    );
  });

  group('push order saat Lanjutkan', () {
    testWidgets('order dibuat dengan kWh yang dipilih', (tester) async {
      final stub = await _pump(tester);

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      expect(stub.to('/transaction/push-order'), isEmpty);

      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      final call = stub.to('/transaction/push-order').single;
      expect(call.method, 'POST');
      expect(call.data, {
        // Endpoint ini mengeja `chargeboxId` dengan b kecil.
        'chargeboxId': 'CB-SMR-01',
        'connectorId': '1',
        // Tanpa ChargingScope yang memegang pemesanan, id-nya kosong;
        // alur sungguhan mengisinya dari `booked-connector`.
        'reservationId': '',
        'kwh': 20,
      });
      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);
    });

    /// Rincian di halaman konfirmasi datang dari order, bukan dari
    /// perkiraan `/count-kwh` — termasuk biaya listrik yang hanya
    /// dikirim order.
    testWidgets('halaman konfirmasi memakai angka dari order', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      expect(find.text('Biaya Listrik'), findsOneWidget);
      expect(find.text('Rp24.660'), findsOneWidget);
      expect(find.text('Rp740'), findsOneWidget);
      expect(find.text('Rp25.400'), findsOneWidget);
      // Angka perkiraan tidak ikut terbawa.
      expect(find.text('Rp27.135'), findsNothing);
    });

    testWidgets('order yang tertunda dijelaskan, bukan sekadar gagal', (
      tester,
    ) async {
      await _pump(tester, stub: _Stub(orderErrorCode: '16'));

      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi Pengisian'), findsNothing);
      expect(
        find.textContaining('Masih ada pesanan yang belum selesai'),
        findsOneWidget,
      );
    });

    testWidgets('kode tak dikenal memakai pesan asli backend', (tester) async {
      await _pump(tester, stub: _Stub(orderErrorCode: '77'));

      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      // Pesan mentah dari stub, diteruskan apa adanya.
      expect(find.text('Processing Another Request'), findsOneWidget);
    });

    /// Kode 99 dulu lolos apa adanya sebagai "Generic Error"; sejak
    /// tabel kode diketahui ia diterjemahkan jadi gangguan server.
    testWidgets('gangguan server diarahkan mencoba lagi', (tester) async {
      await _pump(tester, stub: _Stub(orderErrorCode: '99'));

      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Server sedang bermasalah. Coba lagi sebentar.'),
        findsOneWidget,
      );
    });

    testWidgets('tanda tangan yang ditolak menunjuk ke kredensial', (
      tester,
    ) async {
      await _pump(tester, stub: _Stub(orderErrorCode: '13'));

      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('kredensial'), findsOneWidget);
    });
  });

  testWidgets('daftar kWh kosong dijelaskan', (tester) async {
    await _pump(tester, stub: _Stub(options: const []));

    expect(find.text('Belum ada pilihan kWh'), findsOneWidget);
  });

  testWidgets('jumlah pilihan ganjil tidak merusak grid', (tester) async {
    await _pump(tester, stub: _Stub(options: const [10, 20, 30, 40, 50]));

    expect(find.text('50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
