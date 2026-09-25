import 'package:flutter/foundation.dart';

import 'charge_point_repository.dart';

/// Berapa kali `ongoing-kwh` dibaca ulang setelah perintah stop.
const _attempts = 5;

/// Jeda antar pembacaan.
const _delay = Duration(seconds: 1);

/// Energi akhir sesi setelah perintah stop terkirim.
///
/// Charger masih menyalurkan daya beberapa saat setelah diminta
/// berhenti, jadi angka pada saat tombol ditekan hampir selalu lebih
/// kecil daripada yang benar-benar tersalur. Fungsi ini membaca
/// `POST /transaction/charging/ongoing-kwh` sampai backend melaporkan
/// sesinya selesai.
///
/// Bila sampai [_attempts] percobaan belum juga selesai, dipakai bacaan
/// terakhir yang berhasil — tetap lebih akurat daripada [fallbackKwh].
/// Kegagalan total mengembalikan [fallbackKwh] apa adanya.
Future<double> readFinalEnergy({
  required ChargePointRepository repository,
  required String orderId,
  required double fallbackKwh,
}) async {
  var latest = fallbackKwh;

  for (var attempt = 0; attempt < _attempts; attempt++) {
    await Future<void>.delayed(_delay);

    try {
      final progress = await repository.fetchChargingProgress(
        orderId: orderId,
      );

      latest = progress.charged;
      debugPrint('[FLOW] Bacaan akhir ${attempt + 1}: $progress');
      if (progress.isFinished) return latest;
    } on Object catch (_) {
      // Dicoba lagi; kalau habis, pakai bacaan terakhir.
    }
  }

  return latest;
}
