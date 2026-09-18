import 'package:dio/dio.dart';

import '../models/charge_box.dart';
import '../models/command_result.dart';
import '../models/session_info.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';

/// Kode sukses pada amplop response backend.
const String _successCode = '00';

/// Kode bisnis yang dikirim edge controller saat permintaan ditolak.
class ChargeErrorCode {
  const ChargeErrorCode._();

  /// "Missing Field: chargePointId" (HTTP 400).
  static const missingField = '07';

  /// "Charging station SIM-123 is not connected" (HTTP 503).
  static const notConnected = '12';

  /// "The charging station rejected the command" (HTTP 409).
  static const rejected = '13';

  /// "There is no charging session running on SIM-123" (HTTP 409).
  static const noRunningSession = '15';
}

/// Akses ke edge controller: daftar charger, mulai, dan hentikan sesi.
///
/// Base URL sudah memuat `/api`, jadi path di sini relatif terhadapnya.
class ChargePointRepository {
  ChargePointRepository({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /list`
  ///
  /// Mengembalikan daftar kosong bila `data.chargePoints` kosong —
  /// itu kondisi normal (tidak ada charger yang sedang terhubung),
  /// bukan error.
  Future<List<ChargeBox>> fetchChargeBoxes({CancelToken? cancelToken}) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/list',
      cancelToken: cancelToken,
    );
    final data = _unwrap(json);

    if (data == null) return const [];

    final chargePoints = data['chargePoints'];
    if (chargePoints is! List) return const [];

    final items = chargePoints.whereType<Map<String, dynamic>>().toList();

    return [
      for (var i = 0; i < items.length; i++)
        ChargeBox.fromJson(items[i], number: i + 1),
    ];
  }

  /// Versi [fetchChargeBoxes] untuk satu charger — dipakai halaman
  /// status untuk memantau sesi yang sedang berjalan. Mengembalikan
  /// null bila charger itu tidak lagi ada di daftar.
  Future<ChargeBox?> fetchChargeBox(
    String chargePointId, {
    CancelToken? cancelToken,
  }) async {
    final boxes = await fetchChargeBoxes(cancelToken: cancelToken);
    for (final box in boxes) {
      if (box.id == chargePointId) return box;
    }
    return null;
  }

  /// `GET /progress?chargePointId=…&connectorId=…`
  ///
  /// Kemajuan sesi pada satu konektor.
  ///
  /// [connectorId] dibuat wajib dengan sengaja. Backend menerima
  /// permintaan tanpa parameter itu dan mengembalikan konektor mana pun
  /// yang sedang aktif — juga mengabaikan salah ejaan seperti
  /// `connecterId` tanpa error. Dua-duanya gagal secara senyap, jadi
  /// pemanggil dipaksa menyebutkan konektornya.
  ///
  /// Mengembalikan null bila backend tidak mengirim `data`, mis. saat
  /// belum pernah ada sesi pada konektor tersebut.
  Future<SessionInfo?> fetchProgress({
    required String chargePointId,
    required int connectorId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/progress',
      query: {
        'chargePointId': chargePointId,
        'connectorId': connectorId,
      },
      cancelToken: cancelToken,
    );
    final data = _unwrap(json);
    return data == null ? null : SessionInfo.fromJson(data);
  }

  /// `POST /start` — meminta charger memulai sesi pengisian.
  ///
  /// Hanya `chargePointId` yang wajib; tanpa itu backend membalas
  /// [ChargeErrorCode.missingField]. `connectorId` menentukan konektor
  /// mana yang dipakai. Gagal dengan [ChargeErrorCode.notConnected]
  /// bila charger sedang tidak terhubung, atau
  /// [ChargeErrorCode.rejected] bila charger menolak perintahnya.
  ///
  /// [targetKwh] adalah kWh yang dibeli pengguna — batas berapa banyak
  /// energi yang boleh disalurkan sesi ini. Diambil dari nominal yang
  /// dipilih; dihilangkan dari body bila tidak diketahui, mis. pada
  /// sesi yang dilanjutkan tanpa data pembelian.
  Future<CommandResult> startCharging({
    required String chargePointId,
    required int connectorId,
    double? targetKwh,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/start',
      body: {
        'chargePointId': chargePointId,
        'connectorId': connectorId,
        'targetKwh': ?targetKwh,
      },
      cancelToken: cancelToken,
    );
    return CommandResult.fromJson(_unwrap(json));
  }

  /// `POST /stop` — menghentikan sesi yang sedang berjalan.
  ///
  /// [connectorId] disertakan agar perintahnya mengenai konektor yang
  /// tepat pada charger dengan lebih dari satu konektor.
  ///
  /// Gagal dengan [ChargeErrorCode.noRunningSession] bila tidak ada
  /// sesi aktif pada charger tersebut.
  Future<CommandResult> stopCharging({
    required String chargePointId,
    required int connectorId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/stop',
      body: {
        'chargePointId': chargePointId,
        'connectorId': connectorId,
      },
      cancelToken: cancelToken,
    );
    return CommandResult.fromJson(_unwrap(json));
  }

  /// Memeriksa amplop response dan mengembalikan isi `data`.
  ///
  /// Backend membalas 4xx/5xx untuk kegagalan, jadi ini terutama
  /// menangkap kasus status 2xx tapi `responseCode` bukan "00".
  Map<String, dynamic>? _unwrap(Map<String, dynamic> json) {
    final code = json['responseCode'] as String?;
    if (code != _successCode) {
      throw ApiException(
        type: ApiErrorType.badRequest,
        message: json['responseMessage'] as String? ??
            'Backend menolak permintaan (kode $code).',
        responseCode: code,
        data: json,
      );
    }

    final data = json['data'];
    return data is Map<String, dynamic> ? data : null;
  }
}
