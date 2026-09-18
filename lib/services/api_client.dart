import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import 'api_exception.dart';
import 'api_logger.dart';

/// Pembungkus tunggal di atas Dio.
///
/// Seluruh akses REST lewat sini supaya base URL, timeout, header, dan
/// penerjemahan error hanya diatur di satu tempat. Repository cukup
/// memanggil [get] / [post] / [put] / [delete] dan menangkap
/// [ApiException].
class ApiClient {
  ApiClient._(this._dio);

  /// Instance bersama untuk seluruh aplikasi.
  static final ApiClient instance = ApiClient._(_build());

  /// Dipakai di test untuk menyuntik Dio tiruan.
  @visibleForTesting
  factory ApiClient.withDio(Dio dio) = ApiClient._;

  final Dio _dio;

  /// Akses langsung bila butuh fitur Dio yang belum dibungkus
  /// (upload multipart, download, dsb).
  Dio get raw => _dio;

  static Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: Env.connectTimeout,
        receiveTimeout: Env.receiveTimeout,
        sendTimeout: Env.sendTimeout,
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        headers: {
          'Accept': Headers.jsonContentType,
          if (Env.hasAuthorization) 'Authorization': Env.apiAuthorization,
        },
        // Status divalidasi sendiri supaya 4xx/5xx tetap masuk ke
        // DioException dan diterjemahkan oleh ApiException.
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    if (kDebugMode && Env.enableApiLog) {
      dio.interceptors.add(ApiLogger());
    }

    return dio;
  }

  /// Pasang interceptor tambahan, mis. penyisip token setelah login.
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// Ganti header Authorization saat runtime (mis. setelah login).
  /// Kirim null untuk menghapusnya.
  set authorization(String? value) {
    if (value == null || value.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = value;
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.get<T>(path, queryParameters: query, cancelToken: cancelToken),
    );
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.post<T>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
      ),
    );
  }

  Future<T> put<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.put<T>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
      ),
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.delete<T>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
      ),
    );
  }

  /// Menjalankan request dan menerjemahkan semua kegagalan menjadi
  /// [ApiException], termasuk body yang kosong saat T tidak nullable.
  Future<T> _send<T>(Future<Response<T>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;

      if (data == null && null is! T) {
        throw ApiException(
          type: ApiErrorType.unknown,
          message: 'Server mengembalikan body kosong.',
          statusCode: response.statusCode,
        );
      }

      return data as T;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
