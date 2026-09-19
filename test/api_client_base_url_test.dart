import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/services/api_client.dart';

void main() {
  group('ApiClient.baseUrl', () {
    test('alamat tanpa skema dilengkapi menjadi http', () {
      final dio = Dio();
      ApiClient.withDio(dio).baseUrl = '192.168.1.10:8080';

      expect(dio.options.baseUrl, 'http://192.168.1.10:8080');
    });

    test('https tetap https', () {
      final dio = Dio();
      ApiClient.withDio(dio).baseUrl =
          'https://edge-controller-playground.lentera-app.id/api';

      expect(
        dio.options.baseUrl,
        'https://edge-controller-playground.lentera-app.id/api',
      );
    });

    test('garis miring di ujung dibuang agar path tidak jadi //', () {
      final dio = Dio();
      ApiClient.withDio(dio).baseUrl = 'http://10.0.2.2:8080/';

      expect(dio.options.baseUrl, 'http://10.0.2.2:8080');
    });

    test('alamat bisa diganti berkali-kali tanpa menumpuk', () {
      final dio = Dio();
      final client = ApiClient.withDio(dio);

      client.baseUrl = '192.168.1.10:8080';
      client.baseUrl = '10.0.2.2';

      expect(dio.options.baseUrl, 'http://10.0.2.2');
      expect(client.baseUrl, 'http://10.0.2.2');
    });

    /// Kelonggaran sertifikat hanya berlaku untuk alamat lokal, jadi
    /// adapter-nya harus ikut diganti saat pindah ke host publik —
    /// bukan disetel sekali saat aplikasi dibangun.
    test('adapter diperbarui tiap kali alamat berganti', () {
      final dio = Dio();
      final client = ApiClient.withDio(dio);

      client.baseUrl = '192.168.1.10:8080';
      final forLocal = dio.httpClientAdapter;

      client.baseUrl = 'https://edge-controller-playground.lentera-app.id/api';
      expect(dio.httpClientAdapter, isNot(same(forLocal)));
    });
  });
}
