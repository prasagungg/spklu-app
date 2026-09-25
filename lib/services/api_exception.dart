import 'package:dio/dio.dart';

/// Jenis kegagalan yang perlu dibedakan di UI.
enum ApiErrorType {
  /// Tidak ada koneksi, DNS gagal, host tidak bisa dijangkau.
  network,
  timeout,

  /// 401 / 403
  unauthorized,

  /// 404
  notFound,

  /// 4xx selain di atas
  badRequest,

  /// 5xx
  server,
  cancelled,
  unknown,
}

/// Error yang sudah diterjemahkan ke pesan berbahasa Indonesia, supaya
/// widget tidak perlu tahu soal [DioException].
class ApiException implements Exception {
  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.responseCode,
    this.data,
  });

  final ApiErrorType type;
  final String message;
  final int? statusCode;

  /// Kode bisnis dari amplop backend, mis. "12" (charger tidak
  /// terhubung) atau "15" (tidak ada sesi berjalan).
  final String? responseCode;

  /// Body response mentah, berguna saat backend mengirim detail error.
  final dynamic data;

  factory ApiException.from(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final code = _responseCode(data);

    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => ApiException(
        type: ApiErrorType.timeout,
        message: 'Server tidak merespons. Coba lagi sebentar.',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
      DioExceptionType.connectionError => const ApiException(
        type: ApiErrorType.network,
        message: 'Tidak dapat terhubung ke server. Periksa jaringan Anda.',
      ),
      DioExceptionType.cancel => const ApiException(
        type: ApiErrorType.cancelled,
        message: 'Permintaan dibatalkan.',
      ),
      DioExceptionType.badCertificate => const ApiException(
        type: ApiErrorType.network,
        message: 'Sertifikat server tidak valid.',
      ),
      DioExceptionType.badResponse => _fromStatus(status, data),
      _ => ApiException(
        type: ApiErrorType.unknown,
        message: 'Terjadi kesalahan: ${e.message ?? 'tidak diketahui'}',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
    };
  }

  static ApiException _fromStatus(int? status, dynamic data) {
    final message = _serverMessage(data);
    final code = _responseCode(data);

    return switch (status) {
      401 || 403 => ApiException(
        type: ApiErrorType.unauthorized,
        message: message ?? 'Akses ditolak. Periksa kredensial Anda.',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
      404 => ApiException(
        type: ApiErrorType.notFound,
        message: message ?? 'Data yang diminta tidak ditemukan.',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
      _ when status != null && status >= 500 => ApiException(
        type: ApiErrorType.server,
        message: message ?? 'Server sedang bermasalah ($status).',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
      _ when status != null && status >= 400 => ApiException(
        type: ApiErrorType.badRequest,
        message: message ?? 'Permintaan ditolak server ($status).',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
      _ => ApiException(
        type: ApiErrorType.unknown,
        message: message ?? 'Respons server tidak dikenali.',
        statusCode: status,
        responseCode: code,
        data: data,
      ),
    };
  }

  /// Ambil pesan dari body. `responseMessage` didahulukan karena itu
  /// yang dipakai edge controller, mis. "Charging station SIM-123 is
  /// not connected".
  static String? _serverMessage(dynamic data) {
    if (data is Map) {
      for (final key in ['responseMessage', 'message', 'error', 'msg']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String? _responseCode(dynamic data) =>
      data is Map && data['responseCode'] is String
      ? data['responseCode'] as String
      : null;

  bool get isNetworkIssue =>
      type == ApiErrorType.network || type == ApiErrorType.timeout;

  @override
  String toString() => 'ApiException($type, $statusCode): $message';
}
