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
