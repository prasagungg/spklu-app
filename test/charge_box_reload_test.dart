import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

import 'fixtures.dart';

class _Counter extends Interceptor {
  int listCalls = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/list-chargerbox') listCalls++;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: options.path == '/list-chargerbox' ? _list : _ok,
        statusCode: 200,
      ),
    );
  }
}

const _ok = okResponse;

final _list = listResponse([chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01')]);

void main() {
  testWidgets('daftar dimuat ulang tiap kembali ke Pilih Charge Box',
      (tester) async {
    final counter = _Counter();
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(counter)),
    );

    await tester.pumpWidget(
      SPKLUApp(repository: repo),
    );
    await tester.pumpAndSettle();

    expect(counter.listCalls, greaterThanOrEqualTo(1),
        reason: 'pemuatan awal');
    expect(find.text('CB-SMR-01'), findsOneWidget);

    // Masuk ke bottom sheet lalu ke Pilih Nominal.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih Nominal'), findsOneWidget);
    final beforeBack = counter.listCalls;

    // Kembali lewat tombol Kembali.
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih Charge Box'), findsOneWidget);
    expect(counter.listCalls, greaterThan(beforeBack),
        reason: 'kembali harus memuat ulang');

    // Masuk lebih dalam, lalu pulang lewat tombol Home.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    expect(find.text('Konfirmasi Pengisian'), findsOneWidget);
    final beforeHome = counter.listCalls;

    await tester.tap(find.byType(HomeButton).last);
    await tester.pumpAndSettle();

    expect(find.text('Pilih Charge Box'), findsOneWidget);
    expect(
      counter.listCalls,
      greaterThan(beforeHome),
      reason: 'pulang lewat tombol Home juga harus memuat ulang',
    );
  });
}
