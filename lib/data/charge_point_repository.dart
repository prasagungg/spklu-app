import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/charge_box.dart';
import '../models/connector_check.dart';
import '../models/billing.dart';
import '../models/charging_detail.dart';
import '../models/charging_progress.dart';
import '../models/kwh_price.dart';
import '../models/order.dart';
import '../models/reservation.dart';
import '../models/session_check.dart';
import '../models/transaction_detail.dart';
import '../models/transaction_history.dart';
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

  /// `POST /detail-chargerbox`
  ///
  /// Isi satu charge box beserta status konektornya saat ini.
  ///
  /// ```json
  /// { "chargeboxId": "CB-SMR-01" }
  /// ```
  ///
  /// Dipanggil sekali ketika pengguna menekan sebuah charge box —
  /// status konektor tidak terlihat dari daftar, dan satu panggilan di
  /// sini menggantikan satu panggilan per konektor.
  ///
  /// Jawabannya **tidak membawa `daya`**; yang punya hanya daftar.
  /// Pemanggil karena itu menyalin daya dari charge box di daftar.
  Future<ChargeBox> fetchChargeBoxDetail({
    required String chargeBoxId,
    required int number,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/detail-chargerbox',
      body: {'chargeboxId': chargeBoxId},
      cancelToken: cancelToken,
    );

    return ChargeBox.fromJson(_unwrap(json) ?? const {}, number: number);
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
  /// Membuat order untuk kWh yang dipilih pada pemesanan yang sudah
  /// ada. Inilah yang memberi [Order.orderId] dan
  /// [Order.partnerReference].
  ///
  /// ```json
  /// { "chargeboxId": "CB-SMR-01", "connectorId": "1",
  ///   "reservationId": "U33tiFAl0Yj5TkCQyoUmU", "kwh": 10 }
  /// ```
  ///
  /// [reservationId] wajib — tanpa itu backend membalas
  /// [ResponseCode.missingField].
  ///
  /// Gagal dengan [ResponseCode.processingAnotherRequest] bila masih
  /// ada order tertunda pada konektor itu.
  Future<Order> pushOrder({
    required String chargeBoxId,
    required int connectorId,
    required String reservationId,
    required double kwh,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/push-order',
      body: {
        // Endpoint ini mengeja `chargeboxId` dengan b kecil.
        'chargeboxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        'reservationId': reservationId,
        'kwh': kwh == kwh.roundToDouble() ? kwh.round() : kwh,
      },
      cancelToken: cancelToken,
    );

    return Order.fromJson(_unwrap(json));
  }

  /// `GET /transaction/history-transaction`
  ///
  /// Seluruh transaksi yang pernah tercatat, terbaru lebih dulu.
  ///
  /// **GET tanpa body.** Endpoint ini dulu sebuah POST yang melayani
  /// satu konektor sekali panggil dan mewajibkan `chargeBoxId` serta
  /// `connectorId`, sehingga halaman riwayat harus menanyakan tiap
  /// konektor lalu menggabungkan jawabannya. Sekarang satu panggilan
  /// mengembalikan semuanya dan permintaannya tidak membawa field apa
  /// pun.
  ///
  /// Seperti GET lainnya, tanda tangannya dihitung dengan body kosong
  /// — lihat `SignatureInterceptor`.
  Future<List<TransactionHistoryEntry>> fetchTransactionHistory({
    CancelToken? cancelToken,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/transaction/history-transaction',
      cancelToken: cancelToken,
    );
    final data = _unwrap(json);
    final list = data?['list'];

    if (list is! List) return const [];

    return [
      for (final item in list.whereType<Map<String, dynamic>>())
        TransactionHistoryEntry.fromJson(item),
    ];
  }

  /// `POST /transaction/detail-history-transaction`
  ///
  /// Rincian satu transaksi di riwayat. Kode sesinya wajib — itulah
  /// yang membuktikan transaksi itu memang milik penanya.
  ///
  /// ```json
  /// { "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS", "sessionCode": "30" }
  /// ```
  ///
  /// Gagal dengan [ResponseCode.missingField] tanpa `sessionCode`, dan
  /// [ResponseCode.transactionNotFound] bila kodenya tidak cocok.
  Future<TransactionDetail> fetchTransactionDetail({
    required String orderId,
    required String sessionCode,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/detail-history-transaction',
      body: {'orderId': orderId, 'sessionCode': sessionCode},
      cancelToken: cancelToken,
    );

    return TransactionDetail.fromJson(_unwrap(json));
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
  ///   "bankLog": "1231408098812345678100500",
  ///   "merchantId": "000000000000001",
  ///   "terminalId": "00000001" }
  /// ```
  ///
  /// [amount] **harus sama persis dengan `totalAmount` dari inquiry** —
  /// nilai lain, termasuk total order, dibalas
  /// [ResponseCode.amountMismatch]. Itu sebabnya tipenya [num] dan
  /// bukan `int`: tagihan bisa berupa pecahan (25161.156), dan
  /// membulatkannya lebih dulu sudah dihitung sebagai selisih.
  ///
  /// [bankLog] wajib; tanpa itu dibalas [ResponseCode.missingField].
  /// Bawaannya [Env.bankLog], masih tetap karena mesin kartunya belum
  /// ada.
  ///
  /// [merchantId] dan [terminalId] menyebut mesin mana yang menagih.
  /// Keduanya juga masih nilai sementara dari [Env], dengan alasan yang
  /// sama, dan diganti lewat `--dart-define` begitu nomor aslinya ada.
  ///
  /// Aman dipanggil berulang: pembayaran kedua untuk order yang sama
  /// dibalas sukses.
  Future<BillingInquiry> payBilling({
    required String orderId,
    required num amount,
    String? cardNumber,
    String? bankLog,
    String? merchantId,
    String? terminalId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/payment-billing',
      body: {
        'orderId': orderId,
        'amount': amount,
        'cardNumber': cardNumber ?? Env.cardNumber,
        'bankLog': bankLog ?? Env.bankLog,
        'merchantId': merchantId ?? Env.merchantId,
        'terminalId': terminalId ?? Env.terminalId,
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
  /// { "chargeboxId": "CB-SMR-01", "connectorId": "1",
  ///   "sessionCode": "29" }
  /// ```
  ///
  /// Endpoint ini mengeja `chargeboxId` dengan b kecil. Backend
  /// playground menerima kedua ejaan, tetapi yang dikirim mengikuti
  /// spesifikasinya.
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
        'chargeboxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        'sessionCode': sessionCode,
      },
      cancelToken: cancelToken,
    );
    return SessionCheck.fromJson(_unwrap(json));
  }

  /// `POST /check-status-connector`
  ///
  /// Status OCPP satu konektor — inilah yang tahu kabelnya sudah
  /// tercolok atau belum.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1" }
  /// ```
  ///
  /// Di-polling tiap detik oleh halaman Hubungkan Konektor sampai
  /// statusnya menjadi "Preparing". Kedua field wajib; tanpa
  /// `connectorId` backend membalas [ResponseCode.missingField].
  Future<ConnectorCheck> checkConnectorStatus({
    required String chargeBoxId,
    required int connectorId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/check-status-connector',
      body: {
        'chargeBoxId': chargeBoxId,
        'connectorId': connectorId.toString(),
      },
      cancelToken: cancelToken,
    );

    return ConnectorCheck.fromJson(_unwrap(json));
  }

  /// `POST /booked-connector`
  ///
  /// Memesan konektor atas nama pengguna yang sedang memakai unit ini.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1" }
  /// ```
  ///
  /// Tahapnya **tidak dikirim aplikasi** — backend yang menetapkannya
  /// sendiri ("R0" di sini, lalu "R1" begitu ordernya dibuat).
  /// Memanggil endpoint ini lagi tidak menaikkan tahap, melainkan
  /// membuat pemesanan baru.
  ///
  /// [Reservation.accepted] false berarti konektornya sudah diambil
  /// orang lain dan alur tidak boleh lanjut.
  Future<Reservation> bookConnector({
    required String chargeBoxId,
    required int connectorId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/booked-connector',
      body: {
        'chargeBoxId': chargeBoxId,
        // Backend memakai teks untuk nomor konektor, seperti di daftar.
        'connectorId': connectorId.toString(),
      },
      cancelToken: cancelToken,
    );

    return Reservation.fromJson(_unwrap(json));
  }

  /// `POST /cancelled-connector`
  ///
  /// Melepas booking sehingga konektornya bisa diambil orang lain lagi.
  ///
  /// ```json
  /// { "chargeBoxId": "CB-SMR-01", "connectorId": "1",
  ///   "reservationId": "U33tiFAl0Yj5TkCQyoUmU" }
  /// ```
  ///
  /// [reservationId] wajib — tanpa itu backend membalas
  /// [ResponseCode.missingField]. Membatalkan pemesanan di tahap mana
  /// pun berhasil, dan konektor yang tidak dikenal dibalas 404.
  Future<CancellationResult> cancelConnector({
    required String chargeBoxId,
    required int connectorId,
    required String reservationId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/cancelled-connector',
      body: {
        'chargeBoxId': chargeBoxId,
        'connectorId': connectorId.toString(),
        'reservationId': reservationId,
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

  /// `POST /transaction/charging/detail`
  ///
  /// Rincian akhir satu order: kWh yang dibeli dan yang terpakai,
  /// nominal yang dibayar, yang terpakai, dan yang dikembalikan.
  ///
  /// ```json
  /// { "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS" }
  /// ```
  ///
  /// Dipanggil halaman "Pengisian Selesai". Angkanya dipakai apa adanya:
  /// pembukuan backend yang berwenang, bukan hitungan aplikasi.
  Future<ChargingDetail> fetchChargingDetail({
    required String orderId,
    CancelToken? cancelToken,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/transaction/charging/detail',
      body: {'orderId': orderId},
      cancelToken: cancelToken,
    );

    return ChargingDetail.fromJson(_unwrap(json));
  }

  /// Memeriksa amplop response dan mengembalikan isi `data`.
  ///
  /// Backend membalas 4xx/5xx untuk kegagalan, jadi ini terutama
  /// menangkap kasus status 2xx tapi `responseCode` bukan "00".
  ///
  /// `POST /transaction/detail-history-transaction` mengeja amplopnya
  /// `response_code`/`response_message` saat berhasil — tetapi tetap
  /// camelCase saat gagal. Keduanya diterima di sini, jadi satu
  /// endpoint yang menyimpang tidak perlu jalur penguraian sendiri.
  Map<String, dynamic>? _unwrap(Map<String, dynamic> json) {
    final code = (json['responseCode'] ?? json['response_code']) as String?;
    if (code != _successCode) {
      throw ApiException(
        type: ApiErrorType.badRequest,
        message: (json['responseMessage'] ?? json['response_message'])
                as String? ??
            'Backend menolak permintaan (kode $code).',
        responseCode: code,
        data: json,
      );
    }

    final data = json['data'];
    return data is Map<String, dynamic> ? data : null;
  }
}
