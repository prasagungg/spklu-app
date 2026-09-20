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

/// Amplop `GET /progress` untuk sesi yang sedang berjalan.
Map<String, dynamic> progressResponse({
  String chargeBoxId = 'CB-SMR-01',
  int connectorId = 1,
  String state = 'charging',
  int energyWh = 500,
  int powerW = 12000,
}) =>
    {
      'responseCode': '00',
      'responseMessage': 'Success',
      'data': {
        'chargePointId': chargeBoxId,
        'connectorId': connectorId,
        'transactionId': 42,
        'idTag': 'REMOTE',
        'state': state,
        'connectorStatus': state == 'charging' ? 'Charging' : 'Preparing',
        'percent': 30.0,
        'energyWh': energyWh,
        'powerW': powerW,
        'durationSeconds': 60,
        if (state == 'finished') 'stopReason': 'Remote',
        if (state == 'finished')
          'stoppedAt': '2026-09-17T20:58:35.135618667+07:00',
      },
    };

/// Balasan sukses tanpa isi, untuk `/start` dan `/stop`.
const okResponse = {'responseCode': '00', 'responseMessage': 'Success'};
