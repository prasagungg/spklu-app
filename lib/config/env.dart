import 'package:flutter/foundation.dart';

import 'host.dart';

/// Konfigurasi runtime. Semua nilai bisa ditimpa saat build tanpa
/// mengubah kode:
///
/// ```sh
/// flutter run --dart-define=SPKLU_API_BASE_URL=10.0.2.2:8080
/// ```
///
/// Default-nya menunjuk ke environment playground.
class Env {
  const Env._();

  static const String _rawBaseUrl = String.fromEnvironment(
    'SPKLU_API_BASE_URL',
    defaultValue: 'https://edge-controller-playground.lentera-app.id/api',
  );

  /// Base URL yang sudah dibereskan: alamat tanpa skema dianggap
  /// `http://`, dan garis miring di ujung dibuang. Jadi cukup mengetik
  /// `192.168.1.10:8080`.
  ///
  /// Ini hanya nilai awal. Alamat yang benar-benar dipakai ada di
  /// `ApiConfig.baseUrl`, karena operator bisa menggantinya dari
  /// halaman Konfigurasi Server tanpa membangun ulang aplikasi.
  static String get apiBaseUrl => Host.normalizeBaseUrl(_rawBaseUrl);

  /// Header Authorization. Kosong secara default karena endpoint
  /// playground menerima request tanpa auth; isi lewat --dart-define
  /// begitu environment yang dipakai menuntut kredensial.
  static const String apiAuthorization = String.fromEnvironment(
    'SPKLU_API_AUTH',
  );

  /// Lokasi SPKLU tempat unit ini dipasang, dikirim sebagai `idSpklu`
  /// pada `POST /list-chargerbox`.
  ///
  /// Satu unit melayani satu lokasi, jadi nilainya tetap per pemasangan.
  /// Bila nanti perlu diganti di lapangan tanpa membangun ulang, tempat
  /// yang wajar adalah halaman Konfigurasi Server, bersama alamat
  /// server.
  static const String idSpklu = String.fromEnvironment(
    'SPKLU_ID',
    defaultValue: 'SPKLU-SMR',
  );

  /// Identitas pemanggil pada header `client-id`.
  static const String apiClientId = String.fromEnvironment(
    'SPKLU_CLIENT_ID',
    defaultValue: 'edge',
  );

  /// Kunci untuk menandatangani request. Bawaannya kunci environment
  /// pengembangan; environment sungguhan menimpanya lewat
  /// `--dart-define=SPKLU_SECRET_KEY=…` agar kuncinya tidak ikut
  /// tertulis di kode.
  static const String apiSecretKey = String.fromEnvironment(
    'SPKLU_SECRET_KEY',
    defaultValue: 'edge-dev-only',
  );

  /// Kode sesi yang diterima halaman Verifikasi Sesi.
  ///
  /// Masih nilai tetap: backend belum menyediakan cara memverifikasi
  /// kode sesi milik pengguna. Timpa lewat
  /// `--dart-define=SPKLU_SESSION_PIN=…` bila perlu.
  static const String sessionPin = String.fromEnvironment(
    'SPKLU_SESSION_PIN',
    defaultValue: '00',
  );

  /// Jeda antar polling `GET /progress` di halaman status pengisian.
  static const Duration progressPollInterval = Duration(seconds: 1);

  /// Tulis request/response ke konsol. Otomatis mati di release.
  static const bool enableApiLog = bool.fromEnvironment(
    'SPKLU_API_LOG',
    defaultValue: true,
  );

  /// Menyalakan inspektur jaringan di dalam aplikasi — daftar panggilan
  /// REST yang dibuka dengan menekan lama logo di header.
  ///
  /// Bawaannya mengikuti mode build: menyala di debug, mati di release.
  /// Isinya memuat header dan body apa adanya, termasuk tanda tangan
  /// request, jadi di kiosk yang dipakai umum ia sebaiknya tetap mati.
  /// Untuk uji lapangan memakai APK release, nyalakan dengan
  /// `--dart-define=SPKLU_DEBUG_PANEL=true`.
  static const bool enableDebugPanel = bool.fromEnvironment(
    'SPKLU_DEBUG_PANEL',
    defaultValue: kDebugMode,
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);

  static bool get hasAuthorization => apiAuthorization.isNotEmpty;
}
