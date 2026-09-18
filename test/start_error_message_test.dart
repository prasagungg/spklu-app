import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/pages/connect_connector_page.dart';
import 'package:kossotrik/services/api_exception.dart';

ApiException _error(String code, String message) => ApiException(
      type: ApiErrorType.badRequest,
      message: message,
      responseCode: code,
    );

void main() {
  test('charger tidak terhubung diarahkan memilih charge box lain', () {
    final text = startErrorMessage(
      _error(
        ChargeErrorCode.notConnected,
        'Charging station SIM-456 is not connected',
      ),
    );

    expect(text, contains('tidak terhubung'));
    expect(text, contains('Pilih charge box lain'));
  });

  test('perintah ditolak diarahkan memeriksa konektor', () {
    final text = startErrorMessage(
      _error(
        ChargeErrorCode.rejected,
        'The charging station rejected the command',
      ),
    );

    expect(text, contains('konektor'));
  });

  test('kode tak dikenal memakai pesan asli backend', () {
    const original = 'Something the backend knows about';
    expect(startErrorMessage(_error('99', original)), original);
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
