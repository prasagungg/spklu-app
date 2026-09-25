import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Satu panggilan REST yang tercatat untuk ditampilkan di aplikasi.
///
/// Dibuat saat request berangkat lalu dilengkapi ketika jawabannya
/// datang, sehingga permintaan yang masih berjalan pun terlihat di
/// daftar.
class ApiLogEntry {
  ApiLogEntry({
    required this.method,
    required this.path,
    required this.baseUrl,
    required this.startedAt,
    this.query = const {},
    this.requestHeaders = const {},
    this.requestBody,
  });

  final String method;
  final String path;
  final String baseUrl;
  final DateTime startedAt;
  final Map<String, dynamic> query;
  final Map<String, dynamic> requestHeaders;

  /// Body yang benar-benar dikirim. Sudah berupa teks karena
  /// `SignatureInterceptor` menyerialisasinya lebih dulu.
  final String? requestBody;

  int? statusCode;

  /// Kode dan pesan dari amplop backend, mis. "00" / "Success".
  String? responseCode;
  String? responseMessage;

  String? responseBody;

  /// Terisi bila permintaannya gagal sebelum sempat dijawab.
  String? error;

  Duration? elapsed;

  /// Belum ada jawabannya.
  bool get isPending => elapsed == null;

  /// Gagal — entah di jaringan, di status HTTP, atau di amplop backend.
  bool get isFailure =>
      error != null ||
      (statusCode != null && statusCode! >= 400) ||
      (responseCode != null && responseCode != '00');

  /// "POST /list-chargerbox".
  String get title => '$method $path';

  /// Alamat lengkap yang ditembak.
  String get url {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final search = query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';

    return '$base$path$search';
  }

  /// "200", "503", "—" bila masih berjalan atau gagal tanpa status.
  String get statusLabel => statusCode?.toString() ?? (isPending ? '…' : '—');

  /// "312 ms".
  String get elapsedLabel =>
      elapsed == null ? 'berjalan…' : '${elapsed!.inMilliseconds} ms';

  /// "18:40:39.123".
  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(startedAt.hour)}:${two(startedAt.minute)}'
        ':${two(startedAt.second)}'
        '.${startedAt.millisecond.toString().padLeft(3, '0')}';
  }

  /// Seluruh isi entri sebagai teks — dipakai tombol salin, supaya
  /// teknisi bisa menempelkannya ke chat atau tiket.
  String toShareableText() {
    final buffer = StringBuffer()
      ..writeln('$method $url')
      ..writeln('waktu    : $timeLabel')
      ..writeln('durasi   : $elapsedLabel')
      ..writeln('status   : $statusLabel');

    if (responseCode != null) {
      buffer.writeln('kode     : $responseCode ${responseMessage ?? ''}');
    }
    if (error != null) buffer.writeln('error    : $error');

    buffer
      ..writeln()
      ..writeln('--- header ---');
    for (final entry in requestHeaders.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    if (requestBody != null) {
      buffer
        ..writeln()
        ..writeln('--- request ---')
        ..writeln(requestBody);
    }
    if (responseBody != null) {
      buffer
        ..writeln()
        ..writeln('--- response ---')
        ..writeln(responseBody);
    }

    return buffer.toString();
  }
}

/// Riwayat panggilan REST yang disimpan di memori.
///
/// Dibatasi [capacity] entri terbaru supaya sesi kiosk yang berjalan
/// berjam-jam tidak menghabiskan memori. Tidak ada yang ditulis ke
/// penyimpanan: begitu aplikasi ditutup, riwayatnya hilang.
class ApiLogStore extends ChangeNotifier {
  ApiLogStore({this.capacity = 100});

  /// Riwayat bersama yang ditampilkan halaman inspektur.
  static final ApiLogStore instance = ApiLogStore();

  final int capacity;
  final List<ApiLogEntry> _entries = [];

  /// Terbaru lebih dulu.
  List<ApiLogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void add(ApiLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > capacity) _entries.removeLast();
    notifyListeners();
  }

  /// Memberi tahu pendengar bahwa isi sebuah entri berubah — entri
  /// dilengkapi di tempat ketika jawabannya datang.
  void refresh() => notifyListeners();

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

/// Mencatat setiap panggilan REST ke [ApiLogStore].
///
/// Dipasang setelah `SignatureInterceptor` supaya yang tercatat adalah
/// header dan body yang benar-benar dikirim, bukan bentuk sebelum
/// ditandatangani.
class ApiLogRecorder extends Interceptor {
  ApiLogRecorder({ApiLogStore? store, DateTime Function()? now})
    : _store = store ?? ApiLogStore.instance,
      _now = now ?? DateTime.now;

  /// Body dipotong supaya response panjang tidak menahan memori.
  static const int maxBodyChars = 20000;

  static const String _entryKey = 'api_log_entry';

  final ApiLogStore _store;
  final DateTime Function() _now;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final entry = ApiLogEntry(
      method: options.method,
      path: options.path,
      baseUrl: options.baseUrl,
      startedAt: _now(),
      query: Map<String, dynamic>.from(options.queryParameters),
      requestHeaders: Map<String, dynamic>.from(options.headers),
      requestBody: encode(options.data),
    );

    options.extra[_entryKey] = entry;
    _store.add(entry);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _complete(
      response.requestOptions,
      statusCode: response.statusCode,
      data: response.data,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _complete(
      err.requestOptions,
      statusCode: err.response?.statusCode,
      data: err.response?.data,
      error: err.message ?? err.type.name,
    );
    handler.next(err);
  }

  void _complete(
    RequestOptions options, {
    int? statusCode,
    dynamic data,
    String? error,
  }) {
    final entry = options.extra[_entryKey];
    if (entry is! ApiLogEntry) return;

    entry
      ..statusCode = statusCode
      ..error = error
      ..elapsed = _now().difference(entry.startedAt)
      ..responseBody = encode(data);

    if (data is Map) {
      entry
        ..responseCode = data['responseCode'] as String?
        ..responseMessage = data['responseMessage'] as String?;
    }

    _store.refresh();
  }

  /// Mengubah body apa pun menjadi teks, dipotong di [maxBodyChars].
  static String? encode(dynamic data) {
    if (data == null) return null;

    String text;
    try {
      text = data is String ? data : jsonEncode(data);
    } on Object catch (_) {
      text = data.toString();
    }

    return text.length > maxBodyChars
        ? '${text.substring(0, maxBodyChars)}… (dipotong)'
        : text;
  }
}
