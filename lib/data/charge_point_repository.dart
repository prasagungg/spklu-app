import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/charge_box.dart';
import '../models/backend_status.dart';
import '../models/command_result.dart';
import '../models/session_info.dart';
import '../models/spklu.dart';
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

  /// Client yang dipakai repository ini. Dibuka supaya halaman
  /// Konfigurasi Server mengganti alamat pada client yang benar-benar
  /// menembak backend, bukan pada instance bersama yang kebetulan sama
  /// di produksi tetapi berbeda saat client disuntik.
  ApiClient get client => _client;

  /// `POST /list-chargerbox`
  ///
  /// Isi dan charge box di satu lokasi SPKLU. Lokasinya disebut lewat
  /// body `{"idSpklu": …}`; bawaannya [Env.idSpklu], yaitu lokasi
  /// tempat unit ini dipasang.
  ///
  /// Mengembalikan SPKLU kosong bila backend membalas tanpa `data`.
  Future<Spklu> fetchSpklu({String? idSpklu, CancelToken? cancelToken}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/list-chargerbox',
      body: {'idSpklu': idSpklu ?? Env.idSpklu},
      cancelToken: cancelToken,
    );
    final data = _unwrap(json);

    return data == null ? const Spklu.empty() : Spklu.fromJson(data);
  }

  /// Charge box di lokasi ini saja.
  ///
  /// Mengembalikan daftar kosong bila `chargeBoxes` kosong — itu
  /// kondisi normal (tidak ada charger yang terpasang), bukan error.
  Future<List<ChargeBox>> fetchChargeBoxes({CancelToken? cancelToken}) async {
    final spklu = await fetchSpklu(cancelToken: cancelToken);
    return spklu.chargeBoxes;
  }

  /// Versi [fetchChargeBoxes] untuk satu charge box. Mengembalikan null
  /// bila charge box itu tidak lagi ada di daftar.
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

  /// `POST /status-konektor`
  ///
  /// Status sebenarnya satu konektor. Daftar charge box tidak
  /// memperlihatkannya — statusnya baru ketahuan setelah ditanyakan,
  /// jadi ini dipanggil ketika pengguna membuka daftar konektor sebuah
  /// charge box, bukan berkala.
  ///
  /// ```json
  /// { "spkluId": "SPKLU-SMR", "chargeBoxId": "CB-SMR-01",
  ///   "connectorId": "1" }
  /// ```
  ///
  /// Balasannya memuat `connectorStatus` dengan kosakata angka yang
  /// sama seperti daftar — lihat [BackendStatus]:
  ///
  /// ```json
  /// { "spkluId": "SPKLU-SMR", "chargeBoxId": "CB-SMR-01",
  ///   "chargeBoxName": "Kempower Satellite 200 kW",
  ///   "connectorName": "Gun 1", "connectorId": "1",
  ///   "connectorStatus": 1 }
  /// ```
  ///
  /// Konektor yang tidak dikenal dibalas 404. Mengembalikan null bila
  /// backend tidak mengirim `data`.
  Future<int?> fetchConnectorStatus({
    required String chargeBoxId,
    required int connectorId,
    String? idSpklu,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/status-konektor',
      body: {
        'spkluId': idSpklu ?? Env.idSpklu,
        'chargeBoxId': chargeBoxId,
        // Backend memakai teks untuk nomor konektor, seperti di daftar.
        'connectorId': connectorId.toString(),
      },
      cancelToken: cancelToken,
    );
    final data = _unwrap(json);

    return BackendStatus.parse(data?['connectorStatus']);
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
