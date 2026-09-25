import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';

import 'fixtures.dart';

class _Stub extends Interceptor {
  _Stub(this.responder);

  final Map<String, dynamic> Function() responder;

  /// Berapa kali daftar diminta — dipakai membuktikan tidak ada
  /// penyegaran berkala.
  int calls = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/list-chargerbox') calls++;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: responder(),
        statusCode: 200,
      ),
    );
  }
}

Map<String, dynamic> _list(List<String> ids) =>
    listResponse([for (final id in ids) chargeBoxJson(id: id, nama: id)]);

/// Menarik daftar ke bawah, seperti pengguna menyegarkan halaman.
Future<void> pullToRefresh(WidgetTester tester) async {
  await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tarik ke bawah memuat ulang daftar', (tester) async {
    var ids = ['CB-SMR-01'];
    final stub = _Stub(() => _list(ids));
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(stub)),
    );

    await tester.pumpWidget(SPKLUApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.byType(ChargeBoxCard), findsOneWidget);
    expect(find.text('CB-SMR-02'), findsNothing);

    // Charge box kedua menyusul terdaftar di backend.
    ids = ['CB-SMR-01', 'CB-SMR-02'];
    await pullToRefresh(tester);

    expect(find.byType(ChargeBoxCard), findsNWidgets(2));
    expect(find.text('CB-SMR-02'), findsOneWidget);
  });

  testWidgets('charge box yang hilang dari backend ikut hilang saat ditarik', (
    tester,
  ) async {
    var ids = ['CB-SMR-01', 'CB-SMR-02'];
    final stub = _Stub(() => _list(ids));
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(stub)),
    );

    await tester.pumpWidget(SPKLUApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.byType(ChargeBoxCard), findsNWidgets(2));

    ids = ['CB-SMR-01'];
    await pullToRefresh(tester);

    expect(find.byType(ChargeBoxCard), findsOneWidget);
    expect(find.text('CB-SMR-02'), findsNothing);
  });

  /// Penyegaran berkala sengaja dihapus: pemeriksaan status konektor
  /// dilakukan di halaman lain, jadi halaman ini tidak perlu menembak
  /// backend terus-menerus.
  testWidgets('daftar tidak menyegarkan diri sendiri', (tester) async {
    final stub = _Stub(() => _list(['CB-SMR-01']));
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(stub)),
    );

    await tester.pumpWidget(SPKLUApp(repository: repo));
    await tester.pumpAndSettle();

    final afterFirstLoad = stub.calls;
    expect(afterFirstLoad, greaterThan(0));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    expect(stub.calls, afterFirstLoad);
  });
}
