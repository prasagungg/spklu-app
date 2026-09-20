import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/nominal_option.dart';

/// Data dummy untuk demo.
///
/// [nominals] masih dipakai halaman Pilih Nominal — backend belum punya
/// endpoint harga. [chargeBoxes] sudah tidak dipakai alur utama karena
/// halaman pemilihan mengambil daftarnya dari `POST /list-chargerbox`; yang tersisa
/// hanya pemakaiannya di test.
class DemoData {
  const DemoData._();

  static const List<Connector> _acConnectors = [
    Connector(
      id: 1,
      displayName: 'Gun 1',
      typeConnector: 'Type 2',
      currentType: 'AC',
      status: ConnectorStatus.available,
      statusCode: 1,
    ),
  ];

  static const List<Connector> _acConnectorsBusy = [
    Connector(
      id: 1,
      displayName: 'Gun 1',
      typeConnector: 'Type 2',
      currentType: 'AC',
      // 0 bukan salah satu dari empat status yang dikenal, jadi
      // konektornya mati.
      status: ConnectorStatus.unavailable,
      statusCode: 0,
    ),
  ];

  static const List<Connector> _dcConnectors = [
    Connector(
      id: 1,
      displayName: 'Gun 1',
      typeConnector: 'CCS2',
      currentType: 'DC',
      status: ConnectorStatus.available,
      statusCode: 1,
    ),
    Connector(
      id: 2,
      displayName: 'Gun 2',
      typeConnector: 'CCS2',
      currentType: 'DC',
      status: ConnectorStatus.available,
      statusCode: 1,
      estimatedMinutes: 15,
    ),
  ];

  static const List<ChargeBox> chargeBoxes = [
    ChargeBox(
      number: 1,
      id: 'CB-SMR-01',
      displayName: 'CS AC Charger',
      merek: 'Kempower',
      statusCode: 1,
      connectors: _acConnectors,
    ),
    ChargeBox(
      number: 2,
      id: 'CB-SMR-02',
      displayName: 'CS AC Charger',
      merek: 'Kempower',
      statusCode: 1,
      connectors: _acConnectors,
    ),
    // Nomor 03 sengaja tidak tersedia, mengikuti desain Figma.
    ChargeBox(
      number: 3,
      id: 'CB-SMR-03',
      displayName: 'CS AC Charger',
      merek: 'Kempower',
      statusCode: 1,
      connectors: _acConnectorsBusy,
    ),
    ChargeBox(
      number: 4,
      id: 'CB-SMR-04',
      displayName: 'CS DC Charger',
      merek: 'Kempower',
      statusCode: 1,
      connectors: _dcConnectors,
    ),
    ChargeBox(
      number: 5,
      id: 'CB-SMR-05',
      displayName: 'CS DC Charger',
      merek: 'Kempower',
      statusCode: 1,
      connectors: _dcConnectors,
    ),
    ChargeBox(
      number: 6,
      id: 'CB-SMR-06',
      displayName: 'CS DC Charger',
      merek: 'Kempower',
      statusCode: 1,
      connectors: _dcConnectors,
    ),
  ];

  static const List<NominalOption> nominals = [
    // Sengaja hanya 1 kWh: dipakai untuk menguji apakah charger benar
    // berhenti sendiri saat mencapai targetKwh, tanpa perlu mengisi
    // sampai puluhan kWh.
    NominalOption(amount: 20000, kwh: 1, electricityCost: 18500, pbjtTl: 1500),
    NominalOption(amount: 50000, kwh: 19.5, electricityCost: 48500, pbjtTl: 1500),
    NominalOption(amount: 100000, kwh: 39.0, electricityCost: 98500, pbjtTl: 1500),
    NominalOption(amount: 150000, kwh: 58.5, electricityCost: 148500, pbjtTl: 1500),
  ];
}
