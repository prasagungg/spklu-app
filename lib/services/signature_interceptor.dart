import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../config/env.dart';

/// Menandatangani setiap request dengan header `client-id`, `timestamp`,
/// dan `signature`.
///
/// ## Cara tanda tangannya dibentuk
///
/// ```
/// key       = SHA1(secretKey)                    -> hex huruf kecil
/// signature = HMAC-SHA256(body + clientId + timestamp, key)  -> hex
/// ```
///
/// Dua hal yang mudah salah dan menghasilkan tanda tangan yang ditolak
/// server:
///
/// **Kunci HMAC adalah teks hex-nya, bukan byte mentah SHA1.** Skrip
/// acuan memanggil `CryptoJS.HmacSHA256(pesan, key)` dengan `key` berupa
/// String, dan CryptoJS memperlakukan String sebagai UTF-8. Jadi yang
/// dipakai adalah 40 karakter hex itu apa adanya, bukan 20 byte hasil
/// SHA1. Karena itu di sini `utf8.encode(sha1Hex)`.
///
/// **Yang ditandatangani harus persis sama dengan yang dikirim.** Dio
/// biasanya baru mengubah Map menjadi JSON belakangan, sesudah
/// interceptor berjalan — kalau body diserialisasi dua kali secara
/// terpisah, urutan atau spasinya bisa berbeda dan tanda tangannya
/// meleset. Maka body diserialisasi di sini lalu [RequestOptions.data]
/// diganti dengan String hasilnya, sehingga Dio mengirim byte yang sama
/// dengan yang dihitung.
///
/// Request tanpa body — semua GET — ditandatangani dengan body kosong,
/// mengikuti skrip acuan. Query string tidak ikut ditandatangani.
class SignatureInterceptor extends Interceptor {
  SignatureInterceptor({
    String? clientId,
    String? secretKey,
    DateTime Function()? now,
  })  : clientId = clientId ?? Env.apiClientId,
        _secretKey = secretKey ?? Env.apiSecretKey,
        _now = now ?? DateTime.now;

  final String clientId;
  final String _secretKey;

  /// Disuntik di test supaya tanda tangannya bisa dibandingkan dengan
  /// nilai yang sudah diketahui.
  final DateTime Function() _now;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final body = _serializeBody(options);
    final timestamp = formatTimestamp(_now());

    options.headers['client-id'] = clientId;
    options.headers['timestamp'] = timestamp;
    options.headers['signature'] = sign(
      body: body,
      clientId: clientId,
      secretKey: _secretKey,
      timestamp: timestamp,
    );

    handler.next(options);
  }

  /// Mengubah body menjadi teks yang akan benar-benar dikirim, dan
  /// menuliskannya kembali ke [options] supaya Dio tidak
  /// menyerialisasinya ulang dengan cara yang berbeda.
  ///
  /// Mengembalikan string kosong untuk request tanpa body.
  String _serializeBody(RequestOptions options) {
    final data = options.data;

    if (data == null) return '';
    if (data is String) return data;

    // FormData dan stream dikirim apa adanya oleh Dio; menyentuhnya di
    // sini hanya akan merusak body-nya. Belum dipakai aplikasi ini.
    if (data is! Map && data is! List) return '';

    final encoded = jsonEncode(data);
    options.data = encoded;
    return encoded;
  }

  /// `2026-09-19T10:23:45Z` — ISO 8601 UTC tanpa pecahan detik.
  static String formatTimestamp(DateTime time) => time
      .toUtc()
      .toIso8601String()
      .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

  static String sign({
    required String body,
    required String clientId,
    required String secretKey,
    required String timestamp,
  }) {
    final key = sha1.convert(utf8.encode(secretKey)).toString();

    return Hmac(sha256, utf8.encode(key))
        .convert(utf8.encode('$body$clientId$timestamp'))
        .toString();
  }
}
