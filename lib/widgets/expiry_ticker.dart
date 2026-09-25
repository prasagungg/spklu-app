import 'dart:async';

import 'package:flutter/material.dart';

import '../models/charging_session.dart';

/// Detak hitung mundur tenggat sesi untuk halaman yang menaruh pilnya
/// sendiri di kepala halaman.
///
/// **Tenggat habis berarti pulang.** Di tahap mana pun dan lewat jalur
/// mana pun, begitu hitungannya mencapai 00:00 pengguna dikembalikan ke
/// halaman awal: backend menolak perintah lanjutan dengan kode `22`
/// setelah itu, jadi menahan pengguna di layar yang sudah mati hanya
/// membuatnya menekan tombol yang tidak lagi bekerja.
mixin ExpiryTicker<T extends StatefulWidget> on State<T> {
  /// Dipakai bila sesinya tidak membawa tenggat — mode offline dan test.
  static const fallback = Duration(minutes: 10);

  /// Sesi yang tenggatnya dihitung.
  ChargingSession get expirySession;

  /// Sisa waktu yang sedang ditampilkan.
  Duration get remaining => _remaining;
  late Duration _remaining = _remainingNow() ?? fallback;

  Timer? _ticker;

  /// Sisa waktu menurut tenggat sesinya. Null bila sesinya tidak
  /// membawa tenggat.
  Duration? _remainingNow() => expirySession.remainingAt(DateTime.now());

  void startExpiryTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      // Dihitung ulang dari tenggatnya, bukan dikurangi satu detik:
      // angkanya tetap benar walau timernya tersendat atau layarnya
      // sempat ditinggalkan.
      final next = _remainingNow() ?? _remaining - const Duration(seconds: 1);
      if (next.inSeconds <= 0) {
        timer.cancel();
        setState(() => _remaining = Duration.zero);
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      setState(() => _remaining = next);
    });
  }

  /// Menghentikan detaknya.
  ///
  /// Dipanggil halaman yang tahapnya sudah lewat: tanpa itu tenggat yang
  /// habis akan memulangkan pengguna dari layar yang sudah berada di
  /// atas halaman ini.
  void stopExpiryTicker() => _ticker?.cancel();
}
