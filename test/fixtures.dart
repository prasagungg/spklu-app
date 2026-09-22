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
}) =>
    {
      'connectorId': id,
      'chargeBoxId': chargeBoxId,
      'status': status,
      'namaKonektor': nama,
      'typeConnector': type,
      'connectorTypeCurrent': arus,
      'estimationAvailable': estimasi,
    };

Map<String, dynamic> chargeBoxJson({
  String id = 'CB-SMR-01',
  String nama = 'Kempower Satellite 200 kW',
  String merek = 'Kempower',
  int status = 1,
  List<Map<String, dynamic>>? connectors,
}) =>
    {
      'chargeBoxId': id,
      'merek': merek,
      'status': status,
      'namaChargeBox': nama,
      'connectors': connectors ?? [connectorJson(chargeBoxId: id)],
    };

/// Amplop lengkap `POST /list-chargerbox`.
Map<String, dynamic> listResponse([List<Map<String, dynamic>>? chargeBoxes]) => {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'idSpklu': 'SPKLU-SMR',
        'namaSpklu': 'PLN Charging Station Sisingamangaraja',
        'alamatSpklu': 'Jl. Sisingamangaraja No. 1, Jakarta Selatan',
        'status': 1,
        'dayaSpklu': '200 kW',
        'chargeBoxes': chargeBoxes ?? [chargeBoxJson()],
      },
    };

/// Amplop `POST /status-konektor`.
Map<String, dynamic> connectorStatusResponse({
  int status = 1,
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) =>
    {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'spkluId': 'SPKLU-SMR',
        'chargeBoxId': chargeBoxId,
        'chargeBoxName': 'Kempower Satellite 200 kW',
        'connectorName': 'Gun $connectorId',
        'connectorId': connectorId,
        'connectorStatus': status,
      },
    };

/// Amplop `GET /list-kwh`.
Map<String, dynamic> kwhOptionsResponse([List<num> list = const [10, 20, 30]]) =>
    {
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
}) =>
    {
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
}) =>
    {
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
  int totalAmount = 25400,
}) =>
    {
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
  int totalAmount = 25400,
  String bankLog = '1231408098812345678100500',
}) {
  final body = inquiryBillingResponse(
    orderId: orderId,
    totalAmount: totalAmount,
  );
  (body['data'] as Map<String, dynamic>)['bankLog'] = bankLog;

  return body;
}

/// Amplop `POST /manage-sessioncode`.
Map<String, dynamic> sessionCodeResponse({
  String orderId = 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
  String sessionCode = '29',
  // Bawaannya "sedang mengisi": kebanyakan test hanya ingin melewati
  // tahap menunggu konektor. Kirim 2 untuk menguji penungguannya.
  int statusProcess = 3,
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) =>
    {
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
  String stage = 'R0',
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) =>
    {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargeBoxId': chargeBoxId,
        'chargeBoxName': 'Kempower Satellite 200 kW',
        'connectorName': 'Gun $connectorId',
        'connectorId': connectorId,
        'connectorStatus': stage,
        'status': accepted,
      },
    };

/// Amplop `POST /cancelled-connector`.
Map<String, dynamic> cancellationResponse({
  String chargeBoxId = 'CB-SMR-01',
  String connectorId = '1',
}) =>
    {
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
}) =>
    {
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

/// Balasan sukses tanpa isi, untuk `/start` dan `/stop`.
const okResponse = {'responseCode': '00', 'responseMessage': 'Success'};
