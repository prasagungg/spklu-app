import 'dart:async';

import 'package:kossotrik/data/waiting_pause.dart';

/// Dijalankan `flutter_test` sekali untuk setiap berkas test di folder
/// ini, sebelum `main()`-nya.
///
/// Jeda layar tunggu dipatok, tidak diacak. Dua layar tunggu berurutan
/// yang sama-sama acak membuat test alur panjang lolos atau gagal
/// tergantung angka yang keluar: memompa cukup jauh untuk jeda
/// terpanjang berarti melewati layar tunggu berikutnya.
///
/// Angkanya sengaja dipilih **lebih panjang** dari rentang produksi.
/// Test yang berhenti di sebuah layar tunggu memompa waktu lebih pendek
/// dari jedanya; mematoknya di angka pendek justru membuat test-test itu
/// melewati layar yang mereka periksa.
///
/// Dipatok di sini, bukan di tiap berkas, supaya tidak ada test yang
/// diam-diam ketinggalan dan kembali bergantung pada angka acak.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  waitingPause = () => const Duration(seconds: 4);
  await testMain();
}
