/// Pembangun payload `POST /list-chargerbox` untuk test.
///
/// Dikumpulkan di satu berkas supaya perubahan bentuk response cukup
/// diikuti sekali, bukan di belasan test.
library;

/// Satu konektor. [id] dikirim backend sebagai teks, seperti aslinya.
Map<String, dynamic> connectorJson({
  String id = '1',
  String chargeBoxId = 'CB-SMR-01',
  int status = 1,
  String nama = 'Gun 1',
  String type = 'CCS2',
  String arus = 'DC',
  Object? estimasi,
}) => {
  'connectorId': id,
  'chargeboxId': chargeBoxId,
  'status': status,
  'namaKonektor': nama,
  'typeConnector': type,
  'connectorTypeCurrent': arus,
  'estimatimationAvailable': estimasi,
};

Map<String, dynamic> chargeBoxJson({
  String id = 'CB-SMR-01',
  String nama = 'Kempower Satellite 200 kW',
  String merek = 'Kempower',
  String daya = '200 kW',
  bool isActive = true,
  List<Map<String, dynamic>>? connectors,
}) {
  final list = connectors ?? [connectorJson(chargeBoxId: id)];

  return {
    'chargeboxId': id,
    'merek': merek,
    'daya': daya,
    'isActive': isActive,
    'namaChargebox': nama,
    'connectorTotal': list.length,
    'connectors': list,
  };
}

/// Amplop `POST /detail-chargerbox`.
///
/// Sengaja tanpa `daya` — hanya daftar yang mengirimnya.
Map<String, dynamic> chargeBoxDetailResponse({
  String id = 'CB-SMR-01',
  String nama = 'Kempower Satellite 200 kW',
  List<Map<String, dynamic>>? connectors,
}) {
  final box = chargeBoxJson(id: id, nama: nama, connectors: connectors)
    ..remove('daya');

  return {'responseCode': '00', 'responseMessage': 'Success', 'data': box};
}

/// Amplop lengkap `POST /list-chargerbox`.
Map<String, dynamic> listResponse([List<Map<String, dynamic>>? chargeBoxes]) =>
    {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'idSpklu': 'SPKLU-SMR',
        'namaSpklu': 'PLN Charging Station Sisingamangaraja',
        'alamatSpklu': 'Jl. Sisingamangaraja No. 1, Jakarta Selatan',
        'chargeBoxs': chargeBoxes ?? [chargeBoxJson()],
      },
    };

/// Amplop `GET /list-kwh`.
Map<String, dynamic> kwhOptionsResponse([
  List<num> list = const [10, 20, 30],
]) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {'list': list},
};

/// Amplop `POST /count-kwh`.
Map<String, dynamic> countKwhResponse({
  num kwh = 10,
  int rpTotal = 27135,
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargeBoxId': chargeBoxId,
    'connectorId': connectorId,
    'kwh': kwh,
    'rpJaminanSpklu': 0,
    'rpAdmin': 0,
    'rpDiskon': 0,
    'rpPerKwh': 2466.78,
    'rpPpj': 2467,
    'rpPpn': 0,
    'rpTotal': rpTotal,
    'rpLayanan': 0,
    'rpMaterai': 0,
    'idleFee': 0,
  },
};

/// Amplop `POST /transaction/push-order`.
Map<String, dynamic> pushOrderResponse({
  num kwh = 10,
  int rpTotal = 25400,
  String orderId = 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
  String sessionCode = '29',
  String partnerReference = '81067',
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'orderId': orderId,
    'chargeBoxId': 'CB-SMR-01',
    'chargeBoxName': 'Kempower Satellite 200 kW',
    'connectorName': 'Gun 1',
    'connectorId': '1',
    'partnerReference': partnerReference,
    'sessionCode': sessionCode,
    'sessionExpiredTime': '2026-09-22T04:22:14Z',
    'kwh': kwh,
    'rpPerKwh': 2466,
    'rpPpj': 740,
    'rpPpn': 0,
    'rpTotal': rpTotal,
    'rpLayanan': 0,
    'rpMaterai': 0,
    'rpKwh': 24660,
    'idleFee': 0,
    'serviceFee': 0,
  },
};

/// Amplop `POST /transaction/inquiry-billing`.
Map<String, dynamic> inquiryBillingResponse({
  String orderId = 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
  String pspId = 'EM-BNI',
  String cardNumber = '0123456789012345',
  // `num`, bukan `int`: tagihan sungguhan kerap pecahan (25161.156),
  // dan itulah angka yang harus dikirim balik saat membayar.
  num totalAmount = 25400,
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'orderId': orderId,
    'pspId': pspId,
    'cardNumber': cardNumber,
    'amount': totalAmount,
    'fee': 0,
    'idleFee': 0,
    'serviceFee': 0,
    'totalAmount': totalAmount,
    // Backend mengirimnya kosong di sini; yang berlaku dari
    // push-order.
    'sessionCode': '',
  },
};

/// Amplop `POST /transaction/payment-billing`.
///
/// Bentuknya sama dengan inquiry, ditambah `bankLog` sebagai bukti
/// transaksinya.
Map<String, dynamic> paymentBillingResponse({
  String orderId = 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
  num totalAmount = 25400,
  String bankLog = '1231408098812345678100500',
  String sessionExpired = '2026-09-23T09:56:04Z',
}) {
  final body = inquiryBillingResponse(
    orderId: orderId,
    totalAmount: totalAmount,
  );
  final data = body['data'] as Map<String, dynamic>;
  data['bankLog'] = bankLog;
  // Pembayaran memperbarui tenggat sesi; inilah sumber hitung mundur di
  // layar Hubungkan Konektor.
  data['sessionExpired'] = sessionExpired;

  return body;
}

/// Amplop `POST /manage-sessioncode`.
/// Amplop `POST /check-status-connector`.
///
/// Bawaannya "Preparing" — kabel sudah terpasang — karena kebanyakan
/// test hanya ingin melewati tahap menunggu konektor. Kirim "Available"
/// untuk menguji penungguannya.
Map<String, dynamic> connectorStatusResponse({
  String status = 'Preparing',
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargeBoxId': chargeBoxId,
    'chargeboxName': 'Kempower Satellite 200 kW',
    'connectorName': 'Gun $connectorId',
    'connectorId': connectorId,
    'connectorStatus': status,
  },
};

/// Amplop `POST /transaction/detail-history-transaction`.
///
/// Endpoint ini mengeja amplopnya **snake_case** saat berhasil —
/// `response_code`/`response_message` — sedangkan kegagalannya tetap
/// camelCase. Nomor kartunya pun sudah disamarkan backend.
Map<String, dynamic> transactionDetailResponse({
  String orderId = '8XWS0G9RULEYBLHS48ULF6OFH7',
  num rpPesan = 50000,
  num rpPakai = 32500,
  num rpSisa = 17500,
  num kwhPakai = 6.4,
}) => {
  'response_code': '00',
  'response_message': 'Success',
  'data': {
    'orderId': orderId,
    'chargeboxId': 'CB-SMR-01',
    'chargeboxName': 'Kempower Satellite 200 kW',
    'connectorId': 1,
    'connectorName': 'Gun 1',
    'namaSpklu': 'SPKLU PLN PUSAT',
    'pspId': 'EM-BNI',
    'cardNumber': '601••••••••••890',
    'status': 4,
    'tglCatat': '2026-09-23T09:28:44Z',
    'kwhPesan': 10,
    'kwhPakai': kwhPakai,
    'sisaKwh': 3.6,
    'rpPesan': rpPesan,
    'rpPakai': rpPakai,
    'rpSisa': rpSisa,
    'hargaKwh': 2466,
    'rpLayanan': null,
    'rpMaterai': null,
    'firstSoc': null,
    'idleFee': 0,
  },
};

/// Amplop `POST /transaction/charging/detail`.
///
/// Sebagian angkanya memang dikirim backend sebagai teks atau null —
/// `chargeDuration` "120", `rpMaterai` null — jadi fixture ini menirunya
/// apa adanya.
Map<String, dynamic> chargingDetailResponse({
  String orderId = 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
  num kwhPesan = 10,
  num kwhPakai = 6.4,
  num rpPesan = 25400,
  num rpPakai = 16256,
  num rpSisa = 9144,
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'orderId': orderId,
    'chargeboxId': 'CB-SMR-01',
    'chargeboxName': 'Kempower Satellite 200 kW',
    'connectorName': 'Gun 1',
    'connectorId': '1',
    'status': 4,
    'kwhPesan': kwhPesan,
    'kwhPakai': kwhPakai,
    'sisaKwh': 3.6,
    'rpPesan': rpPesan,
    'rpPakai': rpPakai,
    'rpSisa': rpSisa,
    'hargaKwh': 2466,
    'chargeDuration': '120',
    'chargeDurationInMinutes': '2',
    'rpMaterai': null,
    'firstSoc': null,
    'lastSoc': null,
    'idleFee': 0,
    'serviceFee': 0,
    'tglCatat': '2026-09-24T04:08:39Z',
  },
};

Map<String, dynamic> sessionCodeResponse({
  String orderId = 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
  String sessionCode = '29',
  // Bawaannya "sedang mengisi": kebanyakan test hanya ingin melewati
  // tahap menunggu konektor. Kirim 2 untuk menguji penungguannya.
  int statusProcess = 3,
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'orderId': orderId,
    'chargeBoxId': chargeBoxId,
    'chargeBoxName': 'Kempower Satellite 200 kW',
    'connectorName': 'Gun $connectorId',
    'connectorId': connectorId,
    'sessionCode': sessionCode,
    'statusProcess': statusProcess,
  },
};

/// Amplop `POST /booked-connector`.
///
/// [accepted] mengisi field `status`: konektornya bersedia atau tidak.
Map<String, dynamic> bookingResponse({
  bool accepted = true,
  String reservationId = 'RESV-1',
  String sessionCode = '29',
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargeBoxId': chargeBoxId,
    'chargeboxName': 'Kempower Satellite 200 kW',
    'connectorName': 'Gun $connectorId',
    'connectorId': connectorId,
    // Tahapnya ditetapkan backend sendiri.
    'connectorStatus': 'R0',
    'sessionExpired': '2026-09-23T09:56:04Z',
    'reservationId': reservationId,
    'sessionCode': sessionCode,
    'status': accepted,
  },
};

/// Amplop `POST /cancelled-connector`.
Map<String, dynamic> cancellationResponse({
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'chargeBoxId': chargeBoxId,
    'chargeBoxName': 'Kempower Satellite 200 kW',
    'connectorName': 'Gun $connectorId',
    'connectorId': connectorId,
    'statusMessage': 'Connector Cancelled',
  },
};

/// Amplop `POST /transaction/charging/ongoing-kwh`.
Map<String, dynamic> ongoingKwhResponse({
  String orderId = 'ORDER-1',
  num orderKwh = 10,
  num charged = 0,
  num? remaining,
  int status = 2,
  num power = 0,
  int chargeDurationS = 0,
}) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'orderId': orderId,
    'chargeBoxName': 'Kempower Satellite 200 kW',
    'chargeBoxId': 'CB-SMR-01',
    'connectorName': 'Gun 1',
    'orderKwh': orderKwh,
    'charged': charged,
    'remaining': remaining ?? (orderKwh - charged),
    'status': status,
    'lastSoc': null,
    'firstSoc': null,
    'power': power,
    'chargeDurationS': chargeDurationS,
    'chargeDurationM': chargeDurationS ~/ 60,
    'estRemainingTime': 0,
    'powerActiveImport': 0,
    'estimatedCharged': 0,
  },
};

/// Amplop `GET /transaction/history-transaction` — seluruh riwayat
/// dalam satu jawaban.
Map<String, dynamic> historyResponse([List<Map<String, dynamic>>? list]) => {
  'responseCode': '00',
  'responseMessage': 'Success',
  'data': {
    'list':
        list ??
        [
          historyEntryJson(),
          historyEntryJson(
            orderId: '5SZJ9T6XLDUVP26LNPN89PDNA4',
            totalAmount: 50000,
            createdDate: '2026-09-21T09:42:00Z',
          ),
        ],
  },
};

/// Satu entri riwayat. `pspId` dan `cardNumber` kosong berarti
/// transaksinya tidak pernah sampai dibayar.
///
/// Sejak endpoint-nya melayani seluruh riwayat sekali panggil, tiap
/// entri menyebut charge box dan konektornya sendiri.
Map<String, dynamic> historyEntryJson({
  String orderId = '8XWS0G9RULEYBLHS48ULF6OFH7',
  String pspId = 'EM-BNI',
  String cardNumber = '6012345678907890',
  int totalAmount = 12700,
  String createdDate = '2026-09-23T09:28:44Z',
  String chargeBoxId = 'CB-SMR-01',
  String chargeBoxName = 'Kempower Satellite 200 kW',
  Object? connectorId = '1',
  String connectorName = 'Gun 1',
}) => {
  'pspId': pspId,
  'cardNumber': cardNumber,
  'orderId': orderId,
  'totalAmount': totalAmount,
  'createdDate': createdDate,
  'chargeboxId': chargeBoxId,
  'chargeboxName': chargeBoxName,
  'connectorId': connectorId,
  'connectorName': connectorName,
};

/// Balasan sukses tanpa isi, untuk `/start` dan `/stop`.
const okResponse = {'responseCode': '00', 'responseMessage': 'Success'};
