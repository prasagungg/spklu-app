import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/pages/connect_connector_page.dart';
import 'package:kossotrik/services/api_exception.dart';
import 'package:kossotrik/services/response_code.dart';

ApiException _error(String code, String message) => ApiException(
  type: ApiErrorType.badRequest,
  message: message,
  responseCode: code,
);

void main() {
  test('charger tidak terhubung diarahkan memilih charge box lain', () {
    final text = startErrorMessage(
      _error(
        ResponseCode.chargePointOffline,
        'Charging station SIM-456 is not connected',
      ),
    );

    expect(text, contains('tidak terhubung'));
    expect(text, contains('Pilih charge box lain'));
  });

  test('perintah ditolak diarahkan memeriksa konektor', () {
    final text = startErrorMessage(
      _error(
        ResponseCode.commandRejected,
        'The charging station rejected the command',
      ),
    );

    expect(text, contains('konektor'));
  });

  test('charger yang tidak menjawab diarahkan mencoba lagi', () {
    final text = startErrorMessage(
      _error(
        ResponseCode.chargePointTimedOut,
        'The charging station did not answer in time',
      ),
    );

    expect(text, contains('tidak menjawab'));
  });

  test('kode tak dikenal memakai pesan asli backend', () {
    const original = 'Something the backend knows about';
    expect(startErrorMessage(_error('77', original)), original);
  });

  /// `12` dan `13` dulu dipakai sebagai error charger. Sejak tabel kode
  /// backend diketahui, keduanya berarti autentikasi — pesan charger di
  /// situ akan mengirim petugas mengejar hal yang salah.
  group('kode autentikasi tidak menyamar jadi masalah charger', () {
    for (final code in ['11', '12', '13', '14']) {
      test('kode $code menunjuk ke kredensial aplikasi', () {
        final text = startErrorMessage(_error(code, 'Invalid Signature'));

        expect(text, contains('kredensial'));
        expect(text, contains(code));
        expect(text, isNot(contains('charge box')));
        expect(text, isNot(contains('konektor')));
      });
    }
  });

  group('gangguan server', () {
    for (final code in ['96', '98', '99']) {
      test('kode $code diarahkan mencoba lagi', () {
        final text = startErrorMessage(_error(code, 'Link Down'));

        expect(text, contains('Server sedang bermasalah'));
      });
    }
  });

  test('error jaringan tanpa responseCode tetap tampil apa adanya', () {
    const message = 'Tidak dapat terhubung ke server. Periksa jaringan Anda.';
    expect(
      startErrorMessage(
        const ApiException(type: ApiErrorType.network, message: message),
      ),
      message,
    );
  });
}
