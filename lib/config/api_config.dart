import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import 'env.dart';
import 'host.dart';

/// Alamat backend dan kredensial penandatangan yang dipilih operator di
/// halaman Konfigurasi Server.
///
/// Nilai di [Env] hanya menjadi isian awal. Begitu operator menyimpan
/// nilai lain, itulah yang dipakai seluruh aplikasi dan diingat sampai
/// diganti lagi — controller sering berpindah IP dan kredensialnya bisa
/// dirotasi, dan membangun ulang APK hanya untuk itu tidak masuk akal di
/// lapangan.
///
/// ## Dua tempat simpan, dan alasannya
///
/// | Nilai | Disimpan di | Kenapa |
/// |---|---|---|
/// | `baseUrl` | `SharedPreferences` | alamat jaringan, bukan rahasia |
/// | `clientId` | `FlutterSecureStorage` | separuh pasangan kredensial |
/// | `secretKey` | `FlutterSecureStorage` | kunci penandatangan |
///
/// Secret key adalah kunci HMAC yang menandatangani **setiap** request.
/// Menulisnya ke `SharedPreferences` atau berkas JSON berarti
/// menyimpannya sebagai teks polos yang bisa dibaca siapa pun dengan
/// akses ke perangkat — dan tablet ini berdiri di tempat umum.
/// `FlutterSecureStorage` menyimpannya terenkripsi AES-GCM dengan kunci
/// yang dijaga Keystore perangkat.
///
/// `baseUrl` sengaja **tidak** ikut pindah: perangkat yang sudah
/// dipasang di lapangan menyimpan alamatnya di `SharedPreferences`, dan
/// memindahkannya akan menghapus alamat itu pada pembaruan pertama.
class ApiConfig {
  const ApiConfig._();

  static const String _urlKey = 'spklu_api_base_url';
  static const String _clientIdKey = 'spklu_client_id';
  static const String _secretKey = 'spklu_secret_key';

  /// Bawaannya sudah AES-GCM dengan kunci yang dibungkus RSA di
  /// Keystore perangkat; tidak ada yang perlu diatur di sini.
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static String _baseUrl = Env.apiBaseUrl;
  static String _clientId = Env.apiClientId;
  static String _secret = Env.apiSecretKey;

  /// Alamat yang sedang dipakai [ApiClient], sudah dinormalisasi.
  static String get baseUrl => _baseUrl;

  /// Isi header `client-id` pada setiap request.
  static String get clientId => _clientId;

  /// Kunci yang menandatangani setiap request.
  static String get secretKey => _secret;

  /// Membaca nilai tersimpan lalu langsung memasangnya. Dipanggil
  /// sebelum frame pertama supaya halaman mana pun yang menyentuh
  /// backend sudah memakai alamat dan kredensial yang benar.
  ///
  /// Jatuh ke nilai [Env] untuk apa pun yang belum pernah disimpan.
  static Future<String> restore() async {
    final stored = await _readUrl();
    apply(
      baseUrl: stored == null || stored.isEmpty ? Env.apiBaseUrl : stored,
      clientId: await _readSecure(_clientIdKey) ?? Env.apiClientId,
      secretKey: await _readSecure(_secretKey) ?? Env.apiSecretKey,
    );
    return _baseUrl;
  }

  /// Memasang nilai tanpa menyimpannya.
  ///
  /// Dipisahkan dari [remember] supaya konfigurasinya bisa diuji lebih
  /// dulu: yang gagal dihubungi tidak ikut tercatat sebagai pilihan
  /// operator.
  ///
  /// Yang tidak disebutkan dibiarkan apa adanya. [client] diisi dengan
  /// client milik repository yang sedang dipakai, yang di produksi
  /// memang [ApiClient.instance] — menyebutkannya menjaga agar alamat
  /// baru tetap sampai ke client yang benar ketika repository disuntik.
  static void apply({
    String? baseUrl,
    String? clientId,
    String? secretKey,
    ApiClient? client,
  }) {
    if (clientId != null) _clientId = clientId;
    if (secretKey != null) _secret = secretKey;

    if (baseUrl == null) return;
    _baseUrl = Host.normalizeBaseUrl(baseUrl);
    (client ?? ApiClient.instance).baseUrl = _baseUrl;
  }

  /// Menyimpan nilai yang sedang dipakai agar terpakai lagi setelah
  /// aplikasi ditutup.
  ///
  /// Kegagalan menyimpan tidak dianggap fatal — nilainya sudah aktif
  /// untuk sesi ini, jadi operator tidak perlu dihalangi masuk.
  static Future<void> remember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_urlKey, _baseUrl);
    } on Object catch (e) {
      debugPrint('[CONFIG] Alamat backend gagal disimpan: $e');
    }

    await _writeSecure(_clientIdKey, _clientId);
    await _writeSecure(_secretKey, _secret);
  }

  static Future<String?> _readUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_urlKey);
    } on Object catch (e) {
      debugPrint('[CONFIG] Alamat backend gagal dibaca: $e');
      return null;
    }
  }

  /// Null bila belum pernah disimpan, atau bila penyimpanan amannya
  /// tidak tersedia — di test dan di desktop tanpa plugin. Pemanggilnya
  /// jatuh ke nilai [Env].
  static Future<String?> _readSecure(String key) async {
    try {
      final value = await _secure.read(key: key);
      return value == null || value.isEmpty ? null : value;
    } on Object catch (e) {
      debugPrint('[CONFIG] $key gagal dibaca: $e');
      return null;
    }
  }

  static Future<void> _writeSecure(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } on Object catch (e) {
      debugPrint('[CONFIG] $key gagal disimpan: $e');
    }
  }
}
