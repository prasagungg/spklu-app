import 'host.dart';

/// Konfigurasi runtime. Semua nilai bisa ditimpa saat build tanpa
/// mengubah kode:
///
/// ```sh
/// flutter run \
///   --dart-define=SPKLU_API_BASE_URL=10.0.2.2:8080 \
///   --dart-define=SPKLU_API_AUTH="Basic ZWRnZTplZGdlLWRldi1vbmx5"
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

  /// Kode sesi yang diterima halaman Verifikasi Sesi.
  ///
  /// Masih nilai tetap: backend belum menyediakan cara memverifikasi
  /// kode sesi milik pengguna. Timpa lewat
  /// `--dart-define=SPKLU_SESSION_PIN=…` bila perlu.
  static const String sessionPin = String.fromEnvironment(
    'SPKLU_SESSION_PIN',
    defaultValue: '00',
  );

  /// Jeda penyegaran otomatis daftar charge box. Charger bisa
  /// tersambung atau terputus kapan saja, jadi daftarnya tidak boleh
  /// dibiarkan basi selama pengguna memandanginya.
  static const Duration listRefreshInterval = Duration(seconds: 2);

  /// Jeda antar polling `GET /progress` di halaman status pengisian.
  static const Duration progressPollInterval = Duration(seconds: 1);

  /// Jeda antar polling `/list` saat menunggu konektor dipasang ke
  /// kendaraan. Lebih rapat karena pengguna sedang menunggu di depan
  /// charger.
  static const Duration connectorPollInterval = Duration(seconds: 2);

  /// Tulis request/response ke konsol. Otomatis mati di release.
  static const bool enableApiLog = bool.fromEnvironment(
    'SPKLU_API_LOG',
    defaultValue: true,
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);

  static bool get hasAuthorization => apiAuthorization.isNotEmpty;
}
