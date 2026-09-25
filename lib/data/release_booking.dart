import 'package:flutter/material.dart';

import 'charging_scope.dart';

/// Melepas pemesanan konektor yang masih dipegang unit ini, lalu
/// menjalankan [leave] — bawaannya pulang ke halaman awal.
///
/// **Hanya dipanggil dari halaman sebelum order dibuat**: Kode Sesi dan
/// Pilih Nominal. Sejak `POST /transaction/push-order` berhasil, yang
/// menentukan nasib pemesanan adalah ordernya, dan melepas konektornya
/// dari aplikasi hanya membuat order yang sudah ada menggantung.
///
/// Pemesanan dilupakan lebih dulu, baru permintaannya dikirim: dengan
/// begitu ketukan kedua tidak mengirim pembatalan yang sama dua kali.
///
/// Kegagalan permintaan hanya dicatat. Pengguna sudah memutuskan pergi,
/// dan menahannya di layar karena satu permintaan meleset tidak
/// menolong siapa pun — tenggat pemesanan di backend tetap melepasnya.
Future<void> releaseBooking(BuildContext context, {VoidCallback? leave}) async {
  final navigator = Navigator.of(context);
  final scope = ChargingScope.maybeOf(context);
  final booking = scope?.booking;

  void go() {
    if (leave != null) {
      leave();
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  // Sesi yang sudah mengisi bukan pemesanan yang ditinggalkan —
  // membatalkannya akan menghentikan pengisian orang.
  if (scope == null ||
      booking == null ||
      !booking.isHeld ||
      booking.isCharging) {
    go();
    return;
  }

  final chargeBoxId = booking.chargeBoxId!;
  final connectorId = booking.connectorId!;
  final reservationId = booking.reservationId ?? '';
  booking.forget();

  try {
    final result = await scope.repository.cancelConnector(
      chargeBoxId: chargeBoxId,
      connectorId: connectorId,
      reservationId: reservationId,
    );
    debugPrint('[FLOW] Pemesanan dilepas: $result');
  } on Object catch (e) {
    debugPrint('[FLOW] Pemesanan gagal dilepas: $e');
  }

  go();
}
