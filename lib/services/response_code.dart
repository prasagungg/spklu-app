import 'api_exception.dart';

/// Kode `responseCode` pada amplop response backend.
///
/// Daftar lengkapnya, disalin dari definisi backend. Dikumpulkan di satu
/// tempat supaya tidak ada lagi angka yang ditebak di tengah kode —
/// sebelumnya `12`, `13`, dan `15` dipakai sebagai error charger,
/// padahal ketiganya error autentikasi.
class ResponseCode {
  const ResponseCode._();

  /// Berhasil (200).
  static const ok = '00';

  // --- Umum ---

  /// Endpoint atau data yang diminta tidak ada (404).
  static const notFound = '04';

  /// "Invalid field format: %v" (400).
  static const invalidFieldFormat = '05';

  /// Perpindahan status yang tidak sah (400).
  static const invalidStatusTransition = '06';

  /// "Missing Field: %v" (400).
  static const missingField = '07';

  // --- Autentikasi (401) ---
  //
  // Keempatnya berarti konfigurasi aplikasi yang salah, bukan kesalahan
  // pengguna: client id, jam perangkat, atau kunci penanda tangan.

  static const invalidClientId = '11';
  static const invalidTimestamp = '12';
  static const invalidSignature = '13';
  static const unauthorized = '14';

  /// Bentuk permintaan tidak sesuai (400).
  static const badRequestData = '15';

  /// Masih ada permintaan lain yang diproses (409).
  static const processingAnotherRequest = '16';

  // --- Transaksi ---

  /// Order tidak ditemukan (404).
  static const transactionNotFound = '21';

  /// Order sudah kedaluwarsa (410).
  static const transactionExpired = '22';

  /// Order sudah dibayar (409).
  static const transactionAlreadyPaid = '23';

  /// Transaksi gagal (422).
  static const transactionFailed = '24';

  /// Nominal yang dikirim tidak cocok (422).
  static const amountMismatch = '25';

  // --- Charge point ---

  /// "Charging station %s is not connected" (503).
  static const chargePointOffline = '31';

  /// "The charging station rejected the command" (409).
  static const commandRejected = '32';

  /// "The charging station did not answer in time" (504).
  static const chargePointTimedOut = '33';

  /// "There is no charging session running on %s" (409).
  static const noActiveSession = '34';

  /// Lebih dari satu sesi berjalan; konektornya harus disebut (400).
  static const connectorRequired = '35';

  // --- Sisi server ---

  /// Gangguan jaringan di sisi backend (502).
  static const networkError = '96';

  /// Sambungan ke sistem lain putus (503).
  static const linkDown = '98';

  static const internalServerError = '99';

  /// Kode yang berarti aplikasi ini sendiri yang ditolak, bukan
  /// permintaannya.
  static const authFailures = {
    invalidClientId,
    invalidTimestamp,
    invalidSignature,
    unauthorized,
  };

  /// Kode yang berarti gangguan sementara di sisi server.
  static const serverTroubles = {networkError, linkDown, internalServerError};
}

/// Pesan untuk kode yang tidak ditangani khusus oleh suatu halaman.
///
/// Dipakai sebagai cadangan oleh penerjemah pesan di tiap halaman,
/// supaya kegagalan yang sifatnya teknis tidak muncul sebagai kalimat
/// bahasa Inggris dari backend — dan supaya salah konfigurasi tidak
/// menyamar sebagai masalah charger.
String generalErrorMessage(ApiException e) {
  final code = e.responseCode;

  if (code != null && ResponseCode.authFailures.contains(code)) {
    return 'Aplikasi ini ditolak server (kode $code). '
        'Konfigurasi kredensial perlu diperiksa petugas.';
  }
  if (code != null && ResponseCode.serverTroubles.contains(code)) {
    return 'Server sedang bermasalah. Coba lagi sebentar.';
  }

  return e.message;
}
