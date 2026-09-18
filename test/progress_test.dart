import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/services/api_client.dart';

class _Stub extends Interceptor {
  _Stub(this.body);

  final Map<String, dynamic> body;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: body,
        statusCode: 200,
      ),
    );
  }
}

/// Payload nyata saat sesi berjalan.
const _charging = {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargePointId': 'SIM-456',
    'connectorId': 2,
    'transactionId': 1789645579,
    'idTag': 'REMOTE',
    'state': 'charging',
    'connectorStatus': 'Charging',
    'percent': 55.5,
    'energyWh': 127,
    'energyKwh': 0.127,
    'powerW': 12360,
    'durationSeconds': 41,
    'stoppedAt': null,
    'updatedAt': '2026-09-17T18:47:49.569646+07:00',
  },
};

/// Payload nyata setelah dihentikan: powerW null dan ada stopReason.
const _finished = {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargePointId': 'SIM-456',
    'connectorId': 2,
    'transactionId': 1789648928,
    'idTag': 'REMOTE',
    'state': 'finished',
    'connectorStatus': 'Preparing',
    'percent': 55.5,
    'energyWh': 207,
    'powerW': null,
    'durationSeconds': 59,
    'stopReason': 'Remote',
    'stoppedAt': '2026-09-17T20:58:35.135618667+07:00',
    'updatedAt': '2026-09-17T20:58:30.124695885+07:00',
  },
};

(ChargePointRepository, _Stub) _repo(Map<String, dynamic> body) {
  final stub = _Stub(body);
  return (
    ChargePointRepository(
      client: ApiClient.withDio(Dio()..interceptors.add(stub)),
    ),
    stub,
  );
}

void main() {
  test('query memakai ejaan connectorId, bukan connecterId', () async {
    final (repo, stub) = _repo(_charging);

    await repo.fetchProgress(chargePointId: 'SIM-456', connectorId: 2);

    expect(stub.requests.single.method, 'GET');
    expect(stub.requests.single.path, '/progress');
    expect(stub.requests.single.queryParameters, {
      'chargePointId': 'SIM-456',
      'connectorId': 2,
    });
    // Salah ejaan diabaikan diam-diam oleh server dan mengembalikan
    // konektor lain, jadi ejaannya dikunci di sini.
    expect(stub.requests.single.queryParameters.containsKey('connecterId'),
        isFalse);
  });

  test('connectorId selalu ikut terkirim', () async {
    final (repo, stub) = _repo(_charging);

    await repo.fetchProgress(chargePointId: 'SIM-456', connectorId: 1);

    expect(stub.requests.single.queryParameters, {
      'chargePointId': 'SIM-456',
      'connectorId': 1,
    });
  });

  test('sesi berjalan diurai dan Wh dikonversi ke kWh', () async {
    final (repo, _) = _repo(_charging);

    final p = (await repo.fetchProgress(
      chargePointId: 'SIM-456',
      connectorId: 2,
    ))!;

    expect(p.state, 'charging');
    expect(p.isCharging, isTrue);
    expect(p.isFinished, isFalse);
    expect(p.energyWh, 127);
    expect(p.energyKwh, 0.127);
    expect(p.powerKw, 12.36);
    expect(p.percent, 55.5);
    expect(p.duration, const Duration(seconds: 41));
    expect(p.stopReason, isNull);
  });

  test('sesi selesai: powerW null tidak membuat parsing gagal', () async {
    final (repo, _) = _repo(_finished);

    final p = (await repo.fetchProgress(
      chargePointId: 'SIM-456',
      connectorId: 2,
    ))!;

    expect(p.state, 'finished');
    expect(p.isFinished, isTrue);
    expect(p.isCharging, isFalse);
    expect(p.stopReason, 'Remote');
    expect(p.powerW, 0);
    expect(p.energyKwh, 0.207);
    expect(p.stoppedAt, isNotNull);
  });

  test('tanpa data mengembalikan null, bukan melempar', () async {
    final (repo, _) = _repo(const {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': null,
    });

    expect(
      await repo.fetchProgress(chargePointId: 'SIM-456', connectorId: 2),
      isNull,
    );
  });

  test('energyKwh dari backend dipakai apa adanya', () async {
    // Backend mengirim kedua field; yang kWh yang menentukan.
    final (repo, _) = _repo(const {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePointId': 'SIM-123',
        'connectorId': 1,
        'state': 'charging',
        'energyWh': 6,
        'energyKwh': 0.006,
        'powerW': 12480,
      },
    });

    final p = (await repo.fetchProgress(
      chargePointId: 'SIM-123',
      connectorId: 1,
    ))!;

    expect(p.energyWh, 6);
    expect(p.energyKwh, 0.006);
  });

  test('tanpa energyKwh, dihitung dari energyWh', () async {
    final (repo, _) = _repo(const {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePointId': 'SIM-123',
        'connectorId': 1,
        'state': 'charging',
        'energyWh': 6400,
      },
    });

    final p = (await repo.fetchProgress(
      chargePointId: 'SIM-123',
      connectorId: 1,
    ))!;

    expect(p.energyKwh, 6.4);
  });
}
