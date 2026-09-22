import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/charge_box.dart';
import '../models/backend_status.dart';
import '../models/billing.dart';
import '../models/booking.dart';
import '../models/charging_progress.dart';
import '../models/kwh_price.dart';
import '../models/order.dart';
import '../models/session_check.dart';
import '../models/spklu.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';

/// Kode sukses pada amplop response backend.
const String _successCode = ResponseCode.ok;

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

  /// `GET /list-kwh`
  ///
  /// Pilihan kWh yang bisa dibeli, mis. `[10, 20, 30]`.
  Future<List<double>> fetchKwhOptions({CancelToken? cancelToken}) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/list-kwh',
      cancelToken: cancelToken,
    );
    final data = _unwrap(json);
    final list = data?['list'];

    if (list is! List) return const [];

    return [
      for (final value in list)
        if (value is num) value.toDouble(),
    ];
  }

  /// `POST /count-kwh`
  ///
  /// Rincian harga untuk [kwh] pada konektor tertentu. Backend yang
  /// menghitung; aplikasi hanya menampilkan.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1", "kwh": 10 }
  /// ```
  Future<KwhPrice> countKwh({
    required String chargeBoxId,
    required int connectorId,
    required double kwh,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/count-kwh',
      body: {
        'chargeBoxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        // Pilihan selalu bulat; dikirim sebagai angka, bukan teks.
        'kwh': kwh == kwh.roundToDouble() ? kwh.round() : kwh,
      },
      cancelToken: cancelToken,
    );

    return KwhPrice.fromJson(_unwrap(json));
  }

  /// `POST /transaction/push-order`
  ///
  /// Membuat order di backend untuk kWh yang dipilih. Inilah yang
  /// memberi [Order.orderId], [Order.sessionCode], dan
  /// [Order.partnerReference] — tiga hal yang sebelumnya dikarang
  /// aplikasi.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1", "kwh": 10 }
  /// ```
  ///
  /// Gagal dengan [ResponseCode.processingAnotherRequest] bila masih
  /// ada order tertunda pada konektor itu.
  Future<Order> pushOrder({
    required String chargeBoxId,
    required int connectorId,
    required double kwh,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/push-order',
      body: {
        'chargeBoxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        'kwh': kwh == kwh.roundToDouble() ? kwh.round() : kwh,
      },
      cancelToken: cancelToken,
    );

    return Order.fromJson(_unwrap(json));
  }

  /// `POST /transaction/inquiry-billing`
  ///
  /// Menanyakan tagihan satu order untuk kartu tertentu, sebelum
  /// didebit.
  ///
  /// ```json
  /// { "orderId": "QHGQM7SNQ6IY7GQLQDSLTY2RJI",
  ///   "cardNumber": "0123456789012345" }
  /// ```
  ///
  /// [cardNumber] bawaannya [Env.cardNumber] — masih nilai tetap karena
  /// NFC tidak bisa membaca nomor uang elektronik kartunya.
  ///
  /// Gagal dengan [ResponseCode.invalidFieldFormat] bila empat digit
  /// pertamanya tidak dikenal, atau
  /// [ResponseCode.transactionNotFound] bila ordernya tidak ada.
  /// Aman dipanggil berulang: jawabannya sama.
  Future<BillingInquiry> inquiryBilling({
    required String orderId,
    String? cardNumber,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/inquiry-billing',
      body: {
        'orderId': orderId,
        'cardNumber': cardNumber ?? Env.cardNumber,
      },
      cancelToken: cancelToken,
    );

    return BillingInquiry.fromJson(_unwrap(json));
  }

  /// `POST /transaction/payment-billing`
  ///
  /// Membayar tagihan yang sudah ditanyakan.
  ///
  /// ```json
  /// { "orderId": "…", "amount": 145670,
  ///   "cardNumber": "0123456789012345",
  ///   "bankLog": "1231408098812345678100500" }
  /// ```
  ///
  /// [amount] **harus sama persis dengan `totalAmount` dari inquiry** —
  /// nilai lain, termasuk total order, dibalas
  /// [ResponseCode.amountMismatch].
  ///
  /// [bankLog] wajib; tanpa itu dibalas [ResponseCode.missingField].
  /// Bawaannya [Env.bankLog], masih tetap karena mesin kartunya belum
  /// ada.
  ///
  /// Aman dipanggil berulang: pembayaran kedua untuk order yang sama
  /// dibalas sukses.
  Future<BillingInquiry> payBilling({
    required String orderId,
    required int amount,
    String? cardNumber,
    String? bankLog,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/payment-billing',
      body: {
        'orderId': orderId,
        'amount': amount,
        'cardNumber': cardNumber ?? Env.cardNumber,
        'bankLog': bankLog ?? Env.bankLog,
      },
      cancelToken: cancelToken,
    );

    return BillingInquiry.fromJson(_unwrap(json));
  }

  /// `POST /manage-sessioncode`
  ///
  /// Memeriksa kode sesi yang diketik pengguna pada konektor yang
  /// sedang dipakai. Backend yang memutuskan cocok atau tidak — kode
  /// sesinya milik order, bukan sesuatu yang bisa ditebak aplikasi.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1",
  ///   "sessionCode": "29" }
  /// ```
  ///
  /// Jawabannya juga membawa `statusProcess`, yang dipakai halaman
  /// Hubungkan Konektor untuk memantau apakah nozzle sudah tercolok.
  ///
  /// Gagal dengan [ResponseCode.transactionNotFound] bila kodenya tidak
  /// cocok atau sesinya sudah berakhir, dan
  /// [ResponseCode.missingField] tanpa `sessionCode`.
  Future<SessionCheck> verifySessionCode({
    required String chargeBoxId,
    required int connectorId,
    required String sessionCode,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/manage-sessioncode',
      body: {
        'chargeBoxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        'sessionCode': sessionCode,
      },
      cancelToken: cancelToken,
    );
    return SessionCheck.fromJson(_unwrap(json));
  }

  /// `POST /booked-connector`
  ///
  /// Mengunci konektor atas nama pengguna yang sedang memakai unit ini,
  /// lalu menaikkan tahapnya seiring alur pembelian.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1",
  ///   "connectorStatus": "R0" }
  /// ```
  ///
  /// [BookingStage.selected] yang dibalas
  /// [BookingResult.accepted] false berarti konektornya sudah diambil
  /// orang lain. Tahap berikutnya selalu dibalas false dan itu wajar —
  /// lihat [BookingResult.accepted].
  ///
  /// Konektor yang tidak dikenal, dan kode tahap di luar R0–R3, dibalas
  /// 404.
  Future<BookingResult> bookConnector({
    required String chargeBoxId,
    required int connectorId,
    required BookingStage stage,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/booked-connector',
      body: {
        'chargeBoxId': chargeBoxId,
        // Backend memakai teks untuk nomor konektor, seperti di daftar.
        'connectorId': connectorId.toString(),
        'connectorStatus': stage.code,
      },
      cancelToken: cancelToken,
    );

    return BookingResult.fromJson(_unwrap(json));
  }

  /// `POST /cancelled-connector`
  ///
  /// Melepas booking sehingga konektornya bisa diambil orang lain lagi.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1",
  ///   "connectorStatus": "R0" }
  /// ```
  ///
  /// [stage] wajib disertakan — tanpa `connectorStatus` backend membalas
  /// [ResponseCode.missingField]. Nilainya sendiri tidak menentukan
  /// apa pun: booking di tahap mana pun terlepas, dan membatalkan
  /// konektor yang memang tidak dibooking tetap dibalas sukses. Konektor
  /// yang tidak dikenal dibalas 404.
  Future<CancellationResult> cancelConnector({
    required String chargeBoxId,
    required int connectorId,
    BookingStage stage = BookingStage.selected,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/cancelled-connector',
      body: {
        'chargeBoxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        'connectorStatus': stage.code,
      },
      cancelToken: cancelToken,
    );

    return CancellationResult.fromJson(_unwrap(json));
  }

  /// `POST /transaction/charging/start`
  ///
  /// Meminta charger memulai pengisian untuk order ini. Semua yang
  /// dibutuhkan — charge box, konektor, kWh — sudah melekat pada
  /// ordernya, jadi cukup [orderId].
  ///
  /// Gagal dengan [ResponseCode.chargePointOffline] bila charger sedang
  /// tidak terhubung, [ResponseCode.commandRejected] bila charger
  /// menolak, atau [ResponseCode.invalidStatusTransition] bila ordernya
  /// belum siap dimulai.
  Future<void> startCharging({
    required String orderId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/charging/start',
      body: {'orderId': orderId},
      cancelToken: cancelToken,
    );
    _unwrap(json);
  }

  /// `POST /transaction/charging/stop`
  ///
  /// Menghentikan pengisian order ini.
  ///
  /// Gagal dengan [ResponseCode.invalidStatusTransition] bila ordernya
  /// memang sedang tidak mengisi.
  Future<void> stopCharging({
    required String orderId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/charging/stop',
      body: {'orderId': orderId},
      cancelToken: cancelToken,
    );
    _unwrap(json);
  }

  /// `POST /transaction/charging/ongoing-kwh`
  ///
  /// Kemajuan pengisian order ini: kWh yang sudah tersalur, sisanya,
  /// daya, dan durasinya.
  Future<ChargingProgress> fetchChargingProgress({
    required String orderId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/charging/ongoing-kwh',
      body: {'orderId': orderId},
      cancelToken: cancelToken,
    );

    return ChargingProgress.fromJson(_unwrap(json));
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
