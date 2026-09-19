import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import 'env.dart';
import 'host.dart';

/// Alamat backend yang dipilih operator di halaman Konfigurasi Server.
///
/// [Env.apiBaseUrl] hanya menjadi isian awal. Begitu operator menyimpan
/// alamat lain, alamat itulah yang dipakai seluruh aplikasi dan diingat
/// sampai diganti lagi — controller sering berpindah IP, dan membangun
/// ulang APK hanya untuk itu tidak masuk akal di lapangan.
class ApiConfig {
  const ApiConfig._();

  static const String _key = 'spklu_api_base_url';

  static String _baseUrl = Env.apiBaseUrl;

  /// Alamat yang sedang dipakai [ApiClient], sudah dinormalisasi.
  static String get baseUrl => _baseUrl;

  /// Membaca alamat tersimpan lalu langsung memasangnya. Dipanggil
  /// sebelum frame pertama supaya halaman mana pun yang menyentuh
  /// backend sudah memakai alamat yang benar.
  ///
  /// Jatuh ke [Env.apiBaseUrl] bila belum pernah ada yang disimpan.
  static Future<String> restore() async {
    final stored = await _read();
    apply(stored == null || stored.isEmpty ? Env.apiBaseUrl : stored);
    return _baseUrl;
  }

  /// Memasang [raw] ke [ApiClient] tanpa menyimpannya.
  ///
  /// Dipisahkan dari [remember] supaya alamat bisa diuji lebih dulu:
  /// yang gagal dihubungi tidak ikut tercatat sebagai pilihan operator.
  ///
  /// [client] diisi dengan client milik repository yang sedang dipakai,
  /// yang di produksi memang [ApiClient.instance] — menyebutkannya
  /// menjaga agar alamat baru tetap sampai ke client yang benar ketika
  /// repository disuntik.
  static void apply(String raw, {ApiClient? client}) {
    _baseUrl = Host.normalizeBaseUrl(raw);
    (client ?? ApiClient.instance).baseUrl = _baseUrl;
  }

  /// Menyimpan alamat yang sedang dipakai agar terpakai lagi setelah
  /// aplikasi ditutup.
  ///
  /// Kegagalan menyimpan tidak dianggap fatal — alamatnya sudah aktif
  /// untuk sesi ini, jadi operator tidak perlu dihalangi masuk.
  static Future<void> remember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _baseUrl);
    } on Object catch (e) {
      debugPrint('[CONFIG] Alamat backend gagal disimpan: $e');
    }
  }

  static Future<String?> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } on Object catch (e) {
      debugPrint('[CONFIG] Alamat backend gagal dibaca: $e');
      return null;
    }
  }
}
