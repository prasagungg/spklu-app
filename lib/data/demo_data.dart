import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/nominal_option.dart';

/// Data dummy untuk demo.
///
/// [nominals] masih dipakai halaman Pilih Nominal — backend belum punya
/// endpoint harga. [chargeBoxes] sudah tidak dipakai alur utama karena
/// halaman pemilihan mengambil daftarnya dari `GET /list`; yang tersisa
/// hanya pemakaiannya di test.
class DemoData {
  const DemoData._();

  static const List<Connector> _acConnectors = [
    Connector(
      id: 1,
      displayName: 'Type 2 - 22 kW AC',
      status: ConnectorStatus.available,
    ),
  ];

  static const List<Connector> _acConnectorsBusy = [
    Connector(
      id: 1,
      displayName: 'Type 2 - 22 kW AC',
      status: ConnectorStatus.unavailable,
      rawStatus: 'Unavailable',
    ),
  ];

  static const List<Connector> _dcConnectors = [
    Connector(
      id: 1,
      displayName: 'CCS2 - 200 kW DC',
      status: ConnectorStatus.available,
    ),
    Connector(
      id: 2,
      displayName: 'CCS2 - 200 kW DC',
      status: ConnectorStatus.inUse,
      rawStatus: 'Charging',
      estimatedMinutes: 15,
    ),
  ];

  static const List<ChargeBox> chargeBoxes = [
    ChargeBox(
      number: 1,
      id: 'SIM-001',
      displayName: 'CS AC Charger',
      connectors: _acConnectors,
    ),
    ChargeBox(
      number: 2,
      id: 'SIM-002',
      displayName: 'CS AC Charger',
      connectors: _acConnectors,
    ),
    // Nomor 03 sengaja tidak tersedia, mengikuti desain Figma.
    ChargeBox(
      number: 3,
      id: 'SIM-003',
      displayName: 'CS AC Charger',
      connectors: _acConnectorsBusy,
    ),
    ChargeBox(
      number: 4,
      id: 'SIM-004',
      displayName: 'CS DC Charger',
      connectors: _dcConnectors,
    ),
    ChargeBox(
      number: 5,
      id: 'SIM-005',
      displayName: 'CS DC Charger',
      connectors: _dcConnectors,
    ),
    ChargeBox(
      number: 6,
      id: 'SIM-006',
      displayName: 'CS DC Charger',
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
