import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/services/response_code.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/services/api_exception.dart';

import 'fixtures.dart';

/// Interceptor yang menjawab request tanpa menyentuh jaringan.
class _StubAdapter extends Interceptor {
  _StubAdapter(this.body, {this.status = 200, this.captured});

  final Map<String, dynamic> body;
  final int status;

  /// Diisi dengan request yang lewat, untuk memeriksa path dan body.
  final List<RequestOptions>? captured;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    captured?.add(options);

    if (status >= 400) {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            data: body,
            statusCode: status,
          ),
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: body,
        statusCode: status,
      ),
    );
  }
}

const _ok = okResponse;

ChargePointRepository _repositoryReturning(Map<String, dynamic> body) {
  final dio = Dio()..interceptors.add(_StubAdapter(body));
  return ChargePointRepository(client: ApiClient.withDio(dio));
}

void main() {
  test('memetakan dua charge box beserta konektornya', () async {
    final boxes = await _repositoryReturning(
      listResponse([
        chargeBoxJson(
          id: 'CB-SMR-01',
          nama: 'Kempower Satellite 200 kW',
          connectors: [connectorJson(id: '1', chargeBoxId: 'CB-SMR-01')],
        ),
        chargeBoxJson(
          id: 'CB-SMR-02',
          nama: 'Kempower Satellite 400 kW',
          connectors: [
            connectorJson(id: '1', chargeBoxId: 'CB-SMR-02'),
            connectorJson(id: '2', chargeBoxId: 'CB-SMR-02', nama: 'Gun 2'),
          ],
        ),
      ]),
    ).fetchChargeBoxes();

    expect(boxes, hasLength(2));
    expect(boxes[0].badge, '01');
    expect(boxes[0].id, 'CB-SMR-01');
    expect(boxes[0].name, 'Kempower Satellite 200 kW');
    expect(boxes[0].merek, 'Kempower');
    expect(boxes[0].connectorLabel, '1 Konektor');
    expect(boxes[0].isAvailable, isTrue);
    expect(boxes[1].badge, '02');
    expect(boxes[1].connectorLabel, '2 Konektor');
    expect(boxes[1].connectors.map((c) => c.name), ['Gun 1', 'Gun 2']);
  });

  test('keterangan lokasi ikut diurai', () async {
    final spklu = await _repositoryReturning(listResponse()).fetchSpklu();

    expect(spklu.id, 'SPKLU-SMR');
    expect(spklu.nama, 'PLN Charging Station Sisingamangaraja');
    expect(spklu.alamat, contains('Sisingamangaraja'));
    expect(spklu.daya, '200 kW');
    expect(spklu.statusCode, 1);
  });

  test('daftar diminta lewat POST /list-chargerbox dengan idSpklu',
      () async {
    final captured = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(_StubAdapter(listResponse(), captured: captured));

    await ChargePointRepository(client: ApiClient.withDio(dio))
        .fetchChargeBoxes();

    expect(captured.single.method, 'POST');
    expect(captured.single.path, '/list-chargerbox');
    expect(captured.single.data, {'idSpklu': Env.idSpklu});
  });

  test('idSpklu bisa ditentukan pemanggil', () async {
    final captured = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(_StubAdapter(listResponse(), captured: captured));

    await ChargePointRepository(client: ApiClient.withDio(dio))
        .fetchSpklu(idSpklu: 'SPKLU-LAIN');

    expect(captured.single.data, {'idSpklu': 'SPKLU-LAIN'});
  });

  test('chargeBoxes kosong menghasilkan daftar kosong, bukan error',
      () async {
    final boxes = await _repositoryReturning(
      listResponse(const []),
    ).fetchChargeBoxes();

    expect(boxes, isEmpty);
  });

  test('data null ditangani tanpa melempar', () async {
    final boxes = await _repositoryReturning({
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': null,
    }).fetchChargeBoxes();

    expect(boxes, isEmpty);
  });

  test('responseCode selain 00 dilempar sebagai ApiException', () async {
    final call = _repositoryReturning({
      'responseCode': '99',
      'responseMessage': 'Controller tidak merespons',
      'data': null,
    }).fetchChargeBoxes();

    await expectLater(
      call,
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Controller tidak merespons',
        ),
      ),
    );
  });

  test('fetchChargeBox memilih charge box yang diminta', () async {
    final repo = _repositoryReturning(
      listResponse([
        chargeBoxJson(id: 'CB-SMR-01'),
        chargeBoxJson(id: 'CB-SMR-02'),
      ]),
    );

    expect((await repo.fetchChargeBox('CB-SMR-02'))?.id, 'CB-SMR-02');
    expect(await repo.fetchChargeBox('CB-TIDAK-ADA'), isNull);
  });

  group('status konektor', () {
    test('ditanyakan lewat POST /status-konektor', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          _StubAdapter(connectorStatusResponse(status: 3), captured: captured),
        );

      final status = await ChargePointRepository(client: ApiClient.withDio(dio))
          .fetchConnectorStatus(chargeBoxId: 'CB-SMR-01', connectorId: 1);

      expect(status, 3);
      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/status-konektor');
      expect(captured.single.data, {
        'spkluId': Env.idSpklu,
        'chargeBoxId': 'CB-SMR-01',
        // Backend memakai teks untuk nomor konektor.
        'connectorId': '1',
      });
    });

    test('tanpa data mengembalikan null, bukan melempar', () async {
      final repo = _repositoryReturning(const {
        'responseCode': '00',
        'responseMessage': 'Success',
        'data': null,
      });

      expect(
        await repo.fetchConnectorStatus(
          chargeBoxId: 'CB-SMR-01',
          connectorId: 1,
        ),
        isNull,
      );
    });
  });

  group('start & stop', () {

    test('targetKwh dihilangkan bila tidak diketahui', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(_StubAdapter(_ok, captured: captured));

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .startCharging(chargePointId: 'SIM-456', connectorId: 1);

      expect(captured.single.data, {
        'chargePointId': 'SIM-456',
        'connectorId': 1,
      });
    });

    test('/start membawa chargePointId, connectorId, dan targetKwh',
        () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(_StubAdapter(_ok, captured: captured));

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .startCharging(
            chargePointId: 'SIM-456',
            connectorId: 1,
            targetKwh: 19.5,
          );

      expect(captured, hasLength(1));
      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/start');
      expect(captured.single.data, {
        'chargePointId': 'SIM-456',
        'connectorId': 1,
        'targetKwh': 19.5,
      });
    });

    test('/stop dikirim sebagai POST dengan chargePointId dan connectorId',
        () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(_StubAdapter(_ok, captured: captured));

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .stopCharging(chargePointId: 'SIM-123', connectorId: 1);

      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/stop');
      expect(captured.single.data, {
        'chargePointId': 'SIM-123',
        'connectorId': 1,
      });
    });

    test('charger tidak terhubung memunculkan pesan asli dari backend',
        () async {
      // Bentuk nyata dari edge controller: HTTP 503, responseCode "12".
      final dio = Dio()
        ..interceptors.add(
          _StubAdapter(
            const {
              'responseCode': '31',
              'responseMessage': 'Charging station SIM-123 is not connected',
            },
            status: 503,
          ),
        );

      await expectLater(
        ChargePointRepository(client: ApiClient.withDio(dio))
            .startCharging(chargePointId: 'SIM-123', connectorId: 1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message',
                  'Charging station SIM-123 is not connected')
              .having((e) => e.responseCode, 'responseCode',
                  ResponseCode.chargePointOffline)
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('tidak ada sesi berjalan memunculkan pesan asli dari backend',
        () async {
      // Bentuk nyata dari edge controller: HTTP 409, responseCode "15".
      final dio = Dio()
        ..interceptors.add(
          _StubAdapter(
            const {
              'responseCode': '34',
              'responseMessage':
                  'There is no charging session running on SIM-123',
            },
            status: 409,
          ),
        );

      await expectLater(
        ChargePointRepository(client: ApiClient.withDio(dio))
            .stopCharging(chargePointId: 'SIM-123', connectorId: 1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message',
                  'There is no charging session running on SIM-123')
              .having((e) => e.responseCode, 'responseCode',
                  ResponseCode.noActiveSession),
        ),
      );
    });
  });

  group('hasil perintah', () {
    ChargePointRepository repoFor(Map<String, dynamic> body) =>
        ChargePointRepository(
          client: ApiClient.withDio(Dio()..interceptors.add(_StubAdapter(body))),
        );

    test('/start mengembalikan state starting beserta konektornya', () async {
      // Payload nyata dari edge controller.
      final result = await repoFor(const {
        'responseCode': '00',
        'responseMessage': 'Success',
        'data': {
          'chargePointId': 'SIM-456',
          'connectorId': 1,
          'state': 'starting',
        },
      }).startCharging(chargePointId: 'SIM-456', connectorId: 1);

      expect(result.chargePointId, 'SIM-456');
      expect(result.connectorId, 1);
      expect(result.state, 'starting');
      expect(result.isStarting, isTrue);
      expect(result.transactionId, isNull);
    });

    test('response tanpa connectorId tetap terbaca', () async {
      final result = await repoFor(const {
        'responseCode': '00',
        'responseMessage': 'Success',
        'data': {'chargePointId': 'SIM-456', 'state': 'starting'},
      }).startCharging(chargePointId: 'SIM-456', connectorId: 1);

      expect(result.connectorId, isNull);
      expect(result.isStarting, isTrue);
    });

    test('/stop mengembalikan transactionId yang dihentikan', () async {
      final result = await repoFor(const {
        'responseCode': '00',
        'responseMessage': 'Success',
        'data': {
          'chargePointId': 'SIM-456',
          'connectorId': 1,
          'transactionId': 1789648927,
          'state': 'stopping',
        },
      }).stopCharging(chargePointId: 'SIM-456', connectorId: 1);

      expect(result.transactionId, 1789648927);
      expect(result.isStopping, isTrue);
    });
  });
}
