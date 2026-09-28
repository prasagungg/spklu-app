import 'dart:math';

/// Lama sebuah layar tunggu menahan pengguna sebelum berpindah sendiri.
///
/// Diacak, bukan tetap, supaya perpindahannya tidak terasa seperti
/// animasi yang sama diputar ulang setiap sesi.
///
/// Dipusatkan di sini karena dua layar memakainya — "Konektor Terhubung"
/// di mode otomatis dan "Pengisian Dimulai" — dan keduanya harus terasa
/// sama panjang. Mengubah rentangnya cukup di satu tempat.
Duration randomWaitingPause() => Duration(
  seconds: _minSeconds + Random().nextInt(_maxSeconds - _minSeconds + 1),
);

/// Jeda yang benar-benar dipakai layar tunggu.
///
/// Produksi tidak pernah menugasi ini — nilainya selalu
/// [randomWaitingPause]. Yang menggantinya hanya `flutter_test_config`,
/// dengan durasi tetap: dua layar tunggu berurutan yang sama-sama acak
/// membuat test alur panjang lolos atau gagal tergantung angka yang
/// keluar, karena memompa cukup jauh untuk jeda terpanjang berarti
/// melewati layar tunggu berikutnya.
Duration Function() waitingPause = randomWaitingPause;

const _minSeconds = 2;
const _maxSeconds = 4;
