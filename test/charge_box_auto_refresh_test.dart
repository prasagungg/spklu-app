import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/services/api_client.dart';

class _Stub extends Interceptor {
  _Stub(this.responder);

  final Map<String, dynamic> Function() responder;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: responder(),
        statusCode: 200,
      ),
    );
  }
}

Map<String, dynamic> _list(List<String> ids) => {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePoints': [
          for (final id in ids)
            {
              'id': id,
              'connectors': [
                {'id': 1, 'status': 'Available', 'errorCode': 'NoError'},
              ],
            },
        ],
      },
    };

void main() {
  testWidgets('charge box yang tersambung belakangan ikut muncul sendiri',
      (tester) async {
    // Saat aplikasi dibuka, baru satu charger yang tersambung.
    var ids = ['SIM-456'];
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(() => _list(ids)))),
    );

    await tester.pumpWidget(
      SPKLUApp(repository: repo, home: const ChargeBoxPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChargeBoxCard), findsOneWidget);
    expect(find.text('SIM-123'), findsNothing);

    // SIM-123 menyusul tersambung ke controller.
    ids = ['SIM-123', 'SIM-456'];

    // Tanpa menyentuh apa pun, daftar menyegarkan diri tiap 2 detik.
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(ChargeBoxCard), findsNWidgets(2));
    expect(find.text('SIM-123'), findsOneWidget);
    expect(find.text('SIM-456'), findsOneWidget);
  });

  testWidgets('charger yang terputus hilang dari daftar', (tester) async {
    var ids = ['SIM-123', 'SIM-456'];
    final repo = ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(_Stub(() => _list(ids)))),
    );

    await tester.pumpWidget(
      SPKLUApp(repository: repo, home: const ChargeBoxPage()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChargeBoxCard), findsNWidgets(2));

    ids = ['SIM-456'];
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(ChargeBoxCard), findsOneWidget);
    expect(find.text('SIM-123'), findsNothing);
  });
}
