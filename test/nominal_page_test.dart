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

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub({this.options = const [10, 20, 30], this.failCount = false});

  final List<num> options;
  final bool failCount;
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

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options_,
        statusCode: 200,
        data: switch (options_.path) {
          '/list-kwh' => kwhOptionsResponse(options),
          '/count-kwh' => countKwhResponse(
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

Future<_Stub> _pump(WidgetTester tester, {_Stub? stub}) async {
  final it = stub ?? _Stub();
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(it)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: NominalPage(chargeBox: _box, connector: _box.connectors.single),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return it;
}

PrimaryButton _continueButton(WidgetTester tester) => tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Lanjutkan'),
    );

void main() {
  testWidgets('pilihan kWh diambil dari /list-kwh', (tester) async {
    final stub = await _pump(tester);

    expect(stub.to('/list-kwh'), hasLength(1));
    expect(find.text('10,0 kWh'), findsOneWidget);
    expect(find.text('20,0 kWh'), findsOneWidget);
    expect(find.text('30,0 kWh'), findsOneWidget);
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

  testWidgets('memilih kWh menghitung harganya lewat /count-kwh',
      (tester) async {
    final stub = await _pump(tester);

    await tester.tap(find.text('20,0 kWh'));
    await tester.pumpAndSettle();

    final call = stub.to('/count-kwh').single;
    expect(call.method, 'POST');
    expect(call.data, {
      'chargeBoxId': 'CB-SMR-01',
      'connectorId': '1',
      'kwh': 20,
    });
  });

  testWidgets('rincian harga menampilkan angka dari backend',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('10,0 kWh'));
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

    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();

    // Semuanya nol pada payload ini; deretan "Rp0" hanya menenggelamkan
    // angka yang penting.
    expect(find.text('Biaya Admin'), findsNothing);
    expect(find.text('Bea Materai'), findsNothing);
    expect(find.text('Jaminan SPKLU'), findsNothing);
  });

  testWidgets('ganti pilihan menghitung ulang', (tester) async {
    final stub = await _pump(tester);

    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30,0 kWh'));
    await tester.pumpAndSettle();

    expect(stub.to('/count-kwh'), hasLength(2));
    expect((stub.to('/count-kwh').last.data as Map)['kwh'], 30);
  });

  testWidgets('harga yang gagal dihitung tidak membuka Lanjutkan',
      (tester) async {
    await _pump(tester, stub: _Stub(failCount: true));

    await tester.tap(find.text('10,0 kWh'));
    await tester.pumpAndSettle();

    expect(find.text('Rincian Harga'), findsNothing);
    expect(_continueButton(tester).onPressed, isNull);
    expect(
      find.text('Tidak dapat terhubung ke server. Periksa jaringan Anda.'),
      findsOneWidget,
    );
  });

  testWidgets('daftar kWh kosong dijelaskan', (tester) async {
    await _pump(tester, stub: _Stub(options: const []));

    expect(find.text('Belum ada pilihan kWh'), findsOneWidget);
  });

  testWidgets('jumlah pilihan ganjil tidak merusak grid', (tester) async {
    await _pump(tester, stub: _Stub(options: const [10, 20, 30, 40, 50]));

    expect(find.text('50,0 kWh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
