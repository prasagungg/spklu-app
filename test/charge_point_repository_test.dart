import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/models/connector.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/services/api_exception.dart';

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

const _ok = {'responseCode': '00', 'responseMessage': 'Success'};

ChargePointRepository _repositoryReturning(Map<String, dynamic> body) {
  final dio = Dio()..interceptors.add(_StubAdapter(body));
  return ChargePointRepository(client: ApiClient.withDio(dio));
}

void main() {
  test('memetakan dua charge point beserta konektornya', () async {
    final boxes = await _repositoryReturning({
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePoints': [
          {
            'id': 'SIM-123',
            'vendor': 'Icon Digital',
            'model': 'OCPP Simulator',
            'serialNumber': 'SIM-123',
            'firmwareVersion': 'sim-1.0.0',
            'connectedAt': '2026-09-17T18:41:23.507741+07:00',
            'lastHeartbeat': null,
            'connectors': [
              {'id': 1, 'status': 'Available', 'errorCode': 'NoError', 'session': null},
            ],
          },
          {
            'id': 'SIM-456',
            'vendor': 'Icon Digital',
            'model': 'OCPP Simulator',
            'serialNumber': 'SIM-456',
            'firmwareVersion': 'sim-1.0.0',
            'connectedAt': '2026-09-17T18:41:26.039254+07:00',
            'lastHeartbeat': null,
            'connectors': [
              {'id': 1, 'status': 'Available', 'errorCode': 'NoError', 'session': null},
              {'id': 2, 'status': 'Available', 'errorCode': 'NoError', 'session': null},
            ],
          },
        ],
      },
    }).fetchChargeBoxes();

    expect(boxes, hasLength(2));
    expect(boxes[0].badge, '01');
    expect(boxes[0].name, 'SIM-123');
    expect(boxes[0].connectorLabel, '1 Konektor');
    expect(boxes[0].isAvailable, isTrue);
    expect(boxes[1].badge, '02');
    expect(boxes[1].connectorLabel, '2 Konektor');
    expect(boxes[1].connectedAt, isNotNull);
    expect(boxes[1].lastHeartbeat, isNull);
  });

  test('chargePoints kosong menghasilkan daftar kosong, bukan error', () async {
    final boxes = await _repositoryReturning({
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {'chargePoints': <dynamic>[]},
    }).fetchChargeBoxes();

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

  test('status OCPP dipetakan ke tiga kelompok UI', () async {
    final boxes = await _repositoryReturning({
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePoints': [
          {
            'id': 'SIM-789',
            'connectors': [
              {'id': 1, 'status': 'Charging', 'errorCode': 'NoError'},
              {'id': 2, 'status': 'Faulted', 'errorCode': 'GroundFailure'},
              {'id': 3, 'status': 'Available', 'errorCode': 'OverCurrentFailure'},
            ],
          },
        ],
      },
    }).fetchChargeBoxes();

    final connectors = boxes.single.connectors;
    expect(connectors[0].status, ConnectorStatus.inUse);
    expect(connectors[1].status, ConnectorStatus.unavailable);
    // Error code apa pun mengalahkan status "Available".
    expect(connectors[2].status, ConnectorStatus.unavailable);
    // Konektor 1 sedang mengisi — kartunya tetap bisa ditekan untuk
    // membuka layar pemantauan.
    expect(boxes.single.isAvailable, isTrue);
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
              'responseCode': '12',
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
                  ChargeErrorCode.notConnected)
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
              'responseCode': '15',
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
                  ChargeErrorCode.noRunningSession),
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
