import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/services/signature_interceptor.dart';

/// Waktu tetap supaya tanda tangannya bisa dibandingkan dengan nilai
/// yang sudah diketahui.
final _fixedTime = DateTime.utc(2026, 9, 19, 10, 23, 45);
const _timestamp = '2026-09-19T10:23:45Z';

/// Nilai acuan dihitung dari algoritma skrip Postman:
///
/// ```
/// key       = SHA1("edge-dev-only")
/// signature = HMAC-SHA256(body + "edge" + timestamp, key)
/// ```
const _bodySignature =
    'd44bc2af0c7acd5ee69ef25781c95ebc687f7b9d276b1b61413de805cc65e454';
const _emptyBodySignature =
    '3e3d2b7a4350ac408c81630140a59ba5a764e12ea3b3c89730ebeab03dfbdbf0';

/// Menangkap request setelah interceptor tanda tangan berjalan.
class _Capture extends Interceptor {
  RequestOptions? seen;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    seen = options;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {'responseCode': '00'},
      ),
    );
  }
}

/// Dio dengan interceptor tanda tangan berwaktu tetap, lalu penangkap.
({Dio dio, _Capture capture}) _client() {
  final capture = _Capture();
  final dio = Dio(BaseOptions(baseUrl: 'http://contoh.test'))
    ..interceptors.add(SignatureInterceptor(now: () => _fixedTime))
    ..interceptors.add(capture);

  return (dio: dio, capture: capture);
}

void main() {
  group('header tanda tangan', () {
    test('POST membawa client-id, timestamp, dan signature', () async {
      final c = _client();

      await c.dio.post<Map<String, dynamic>>(
        '/start',
        data: {'chargePointId': 'SIM-456', 'connectorId': 1},
      );

      final headers = c.capture.seen!.headers;
      expect(headers['client-id'], 'edge');
      expect(headers['timestamp'], _timestamp);
      expect(headers['signature'], _bodySignature);
    });

    test('GET ditandatangani dengan body kosong', () async {
      final c = _client();

      await c.dio.get<Map<String, dynamic>>(
        '/progress',
        queryParameters: {'chargePointId': 'SIM-456', 'connectorId': 1},
      );

      expect(c.capture.seen!.headers['signature'], _emptyBodySignature);
    });

    /// Kalau body diserialisasi dua kali — sekali untuk ditandatangani,
    /// sekali lagi oleh Dio — hasilnya bisa berbeda dan server menolak.
    /// Interceptor menuliskan JSON-nya kembali ke request agar yang
    /// dikirim persis yang dihitung.
    test('body yang dikirim adalah JSON yang ditandatangani', () async {
      final c = _client();

      await c.dio.post<Map<String, dynamic>>(
        '/start',
        data: {'chargePointId': 'SIM-456', 'connectorId': 1},
      );

      expect(
        c.capture.seen!.data,
        '{"chargePointId":"SIM-456","connectorId":1}',
      );
    });

    test('body yang sudah berupa String tidak diserialisasi ulang',
        () async {
      final c = _client();

      await c.dio.post<Map<String, dynamic>>(
        '/start',
        data: '{"chargePointId":"SIM-456","connectorId":1}',
      );

      expect(c.capture.seen!.headers['signature'], _bodySignature);
    });

    test('body berbeda menghasilkan tanda tangan berbeda', () async {
      final a = _client();
      final b = _client();

      await a.dio.post<Map<String, dynamic>>('/start', data: {'a': 1});
      await b.dio.post<Map<String, dynamic>>('/start', data: {'a': 2});

      expect(
        a.capture.seen!.headers['signature'],
        isNot(b.capture.seen!.headers['signature']),
      );
    });
  });

  group('timestamp', () {
    test('ISO 8601 UTC tanpa pecahan detik', () {
      expect(
        SignatureInterceptor.formatTimestamp(
          DateTime.utc(2026, 9, 19, 10, 23, 45, 123, 456),
        ),
        '2026-09-19T10:23:45Z',
      );
    });

    test('waktu lokal diubah ke UTC lebih dulu', () {
      final local = DateTime.utc(2026, 9, 19, 3, 0, 0).toLocal();

      expect(
        SignatureInterceptor.formatTimestamp(local),
        '2026-09-19T03:00:00Z',
      );
    });

    test('detik bulat tetap diberi akhiran Z', () {
      expect(
        SignatureInterceptor.formatTimestamp(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        '2026-01-02T03:04:05Z',
      );
    });
  });

  group('sign', () {
    /// Kunci HMAC adalah teks hex SHA1, bukan 20 byte mentahnya —
    /// CryptoJS memperlakukan kunci berupa String sebagai UTF-8.
    test('cocok dengan nilai dari skrip acuan', () {
      expect(
        SignatureInterceptor.sign(
          body: '{"chargePointId":"SIM-456","connectorId":1}',
          clientId: 'edge',
          secretKey: 'edge-dev-only',
          timestamp: _timestamp,
        ),
        _bodySignature,
      );
    });

    test('kunci rahasia yang salah menghasilkan tanda tangan lain', () {
      expect(
        SignatureInterceptor.sign(
          body: '',
          clientId: 'edge',
          secretKey: 'salah',
          timestamp: _timestamp,
        ),
        isNot(_emptyBodySignature),
      );
    });
  });

  test('nilai bawaan sesuai environment pengembangan', () {
    expect(Env.apiClientId, 'edge');
    expect(Env.apiSecretKey, 'edge-dev-only');
  });
}
