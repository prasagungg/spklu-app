import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Mencatat setiap panggilan REST ke konsol dengan format satu baris,
/// sehingga terlihat jelas endpoint mana yang ditembak, berapa lama,
/// dan apa jawabannya.
///
/// ```
/// [API] → POST /start {"chargePointId":"SIM-456","connectorId":1}
/// [API] ← 200 POST /start (312ms) code=00 Success
/// [API] ✗ 503 POST /start (118ms) code=12 Charging station SIM-456 is not connected
/// ```
class ApiLogger extends Interceptor {
  ApiLogger({this.maxBodyChars = 1200});

  /// Body dipotong supaya response daftar charge box yang panjang tidak
  /// membanjiri konsol. Batasnya cukup untuk memuat jawaban
  /// `ongoing-kwh` utuh — dulu 400, dan angkanya justru terpotong di
  /// tempat yang paling ingin dilihat saat menelusuri pengisian.
  final int maxBodyChars;

  static const _startKey = 'api_logger_start';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();
    final body = options.data == null ? '' : ' ${_encode(options.data)}';
    debugPrint('[API] → ${options.method} ${options.path}$body');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    debugPrint(
      '[API] ← ${response.statusCode} ${options.method} ${options.path}'
      '${_elapsed(options)} ${_summary(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final status = err.response?.statusCode ?? '-';
    final detail = err.response?.data != null
        ? _summary(err.response!.data)
        : (err.message ?? err.type.name);
    debugPrint(
      '[API] ✗ $status ${options.method} ${options.path}'
      '${_elapsed(options)} $detail',
    );
    handler.next(err);
  }

  String _elapsed(RequestOptions options) {
    final started = options.extra[_startKey];
    if (started is! DateTime) return '';
    return ' (${DateTime.now().difference(started).inMilliseconds}ms)';
  }

  /// Amplop backend diringkas jadi `code=00 Success`; bentuk lain
  /// dicetak apa adanya sampai batas [maxBodyChars].
  String _summary(dynamic data) {
    if (data is Map) {
      final code = data['responseCode'];
      final message = data['responseMessage'];
      if (code != null) {
        final payload = data['data'];
        final extra = payload == null ? '' : ' ${_encode(payload)}';
        return 'code=$code $message$extra';
      }
    }
    return _encode(data);
  }

  String _encode(dynamic data) {
    String text;
    try {
      text = data is String ? data : jsonEncode(data);
    } catch (_) {
      text = data.toString();
    }
    return text.length > maxBodyChars
        ? '${text.substring(0, maxBodyChars)}…'
        : text;
  }
}
