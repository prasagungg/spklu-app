import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/models/connector.dart';
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

ChargePointRepository _repositoryFailing(
  Map<String, dynamic> body, {
  required int status,
}) {
  final dio = Dio()..interceptors.add(_StubAdapter(body, status: status));
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
    // Daya pindah ke tiap charge box; SPKLU tidak lagi mengirimnya.
    expect(spklu.daya, isEmpty);
    expect(spklu.chargeBoxes.single.daya, '200 kW');
    expect(spklu.chargeBoxes.single.isActive, isTrue);
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

  group('detail charge box', () {
    test('diminta lewat POST /detail-chargerbox', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          _StubAdapter(chargeBoxDetailResponse(), captured: captured),
        );

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .fetchChargeBoxDetail(chargeBoxId: 'CB-SMR-01', number: 1);

      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/detail-chargerbox');
      // Ejaan b kecil, mengikuti backend.
      expect(captured.single.data, {'chargeboxId': 'CB-SMR-01'});
    });

    test('status tiap konektor ikut terurai', () async {
      final box = await _repositoryReturning(
        chargeBoxDetailResponse(
          connectors: [
            connectorJson(id: '1', status: 1),
            connectorJson(id: '2', nama: 'Gun 2', status: 2),
          ],
        ),
      ).fetchChargeBoxDetail(chargeBoxId: 'CB-SMR-01', number: 4);

      expect(box.id, 'CB-SMR-01');
      expect(box.badge, '04');
      expect(box.connectors.map((c) => c.status), [
        ConnectorStatus.available,
        ConnectorStatus.inUse,
      ]);
    });

    /// Hanya daftar yang mengirim `daya`; pemanggil menyalinnya sendiri.
    test('detail tidak membawa daya', () async {
      final box = await _repositoryReturning(
        chargeBoxDetailResponse(),
      ).fetchChargeBoxDetail(chargeBoxId: 'CB-SMR-01', number: 1);

      expect(box.daya, isEmpty);
    });
  });

  /// Backend mengeja charge box dengan b kecil di endpoint ini, dan
  /// pernah menamai batas waktunya `sessionExpiredTime` sebelum menjadi
  /// `sessionExpired`. Yang salah eja akan hilang diam-diam.
  test('order menerima kedua ejaan yang dipakai backend', () async {
    final repo = _repositoryReturning({
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'orderId': 'VB4LY6CAI8Z8C25QHMY4MIRJUC',
        'chargeboxId': 'ACMP_UAT',
        'chargeboxName': 'ACMP UAT',
        'connectorName': 'DCCT 200 kW',
        'connectorId': '3',
        'partnerReference': '81067',
        'sessionCode': '65',
        'sessionExpired': '2026-09-24T02:43:44Z',
        'kwh': 10,
        'rpTotal': 2000,
        'serviceFee': 2000,
      },
    });

    final order = await repo.pushOrder(
      chargeBoxId: 'ACMP_UAT',
      connectorId: 3,
      reservationId: 'GiutWg7co_CaODPntGi3c',
      kwh: 10,
    );

    expect(order.chargeBoxId, 'ACMP_UAT');
    expect(order.chargeBoxName, 'ACMP UAT');
    expect(order.sessionExpiredAt, DateTime.utc(2026, 9, 24, 2, 43, 44));
    expect(order.rpTotal, 2000);
    // Biaya jasanya satu-satunya isi tagihan; tanpa barisnya, rincian
    // harga akan menunjukkan deretan nol dengan total 2.000.
    expect(order.extraCharges, contains((label: 'Biaya Jasa', amount: 2000)));
  });

  group('perintah pengisian', () {
    /// Charge box, konektor, dan kWh-nya melekat pada order, jadi
    /// ketiga endpoint pengisian cukup membawa orderId.
    test('start dikirim sebagai POST dengan orderId saja', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(_StubAdapter(_ok, captured: captured));

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .startCharging(orderId: 'ORDER-1');

      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/transaction/charging/start');
      expect(captured.single.data, {'orderId': 'ORDER-1'});
    });

    test('stop dikirim sebagai POST dengan orderId saja', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(_StubAdapter(_ok, captured: captured));

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .stopCharging(orderId: 'ORDER-1');

      expect(captured.single.path, '/transaction/charging/stop');
      expect(captured.single.data, {'orderId': 'ORDER-1'});
    });

    test('charger yang tidak terhubung dilempar sebagai ApiException',
        () async {
      final repo = _repositoryFailing(
        const {
          'responseCode': '31',
          'responseMessage': 'Charging station CB-SMR-01 is not connected',
        },
        status: 503,
      );

      await expectLater(
        repo.startCharging(orderId: 'ORDER-1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.responseCode,
            'responseCode',
            ResponseCode.chargePointOffline,
          ),
        ),
      );
    });

    test('menghentikan yang tidak sedang mengisi dilempar apa adanya',
        () async {
      final repo = _repositoryFailing(
        const {
          'responseCode': '06',
          'responseMessage': 'Invalid Status Transition',
        },
        status: 400,
      );

      await expectLater(
        repo.stopCharging(orderId: 'ORDER-1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.responseCode,
            'responseCode',
            ResponseCode.invalidStatusTransition,
          ),
        ),
      );
    });
  });

  group('kemajuan pengisian', () {
    test('ditanyakan lewat ongoing-kwh dengan orderId', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          _StubAdapter(ongoingKwhResponse(), captured: captured),
        );

      await ChargePointRepository(client: ApiClient.withDio(dio))
          .fetchChargingProgress(orderId: 'ORDER-1');

      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/transaction/charging/ongoing-kwh');
      expect(captured.single.data, {'orderId': 'ORDER-1'});
    });

    /// Endpoint lama melaporkan Wh; yang ini sudah kWh, jadi angkanya
    /// dipakai apa adanya tanpa dibagi seribu.
    test('charged dibaca sebagai kWh apa adanya', () async {
      final progress = await _repositoryReturning(
        ongoingKwhResponse(charged: 6.4, orderKwh: 10),
      ).fetchChargingProgress(orderId: 'ORDER-1');

      expect(progress.charged, 6.4);
      expect(progress.orderKwh, 10);
      expect(progress.remaining, closeTo(3.6, 0.001));
    });

    test('status memakai kosakata yang sama dengan konektor', () async {
      final charging = await _repositoryReturning(
        ongoingKwhResponse(status: 3),
      ).fetchChargingProgress(orderId: 'ORDER-1');
      final finished = await _repositoryReturning(
        ongoingKwhResponse(status: 4),
      ).fetchChargingProgress(orderId: 'ORDER-1');

      expect(charging.isCharging, isTrue);
      expect(charging.isFinished, isFalse);
      expect(finished.isFinished, isTrue);
    });

    test('soc yang null tidak membuat parsing gagal', () async {
      final progress = await _repositoryReturning(
        ongoingKwhResponse(),
      ).fetchChargingProgress(orderId: 'ORDER-1');

      expect(progress.firstSoc, isNull);
      expect(progress.lastSoc, isNull);
      expect(progress.duration, Duration.zero);
    });
  });
}
