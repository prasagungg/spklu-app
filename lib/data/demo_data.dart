import '../config/env.dart';
import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/kwh_price.dart';
import '../models/order.dart';

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

  /// Pilihan kWh untuk mode offline, mengikuti `GET /list-kwh`.
  static const List<double> kwhOptions = [10, 20, 30];

  /// Rincian harga tiruan untuk mode offline.
  ///
  /// Angkanya mengikuti bentuk `POST /count-kwh`, dengan tarif per kWh
  /// yang sama seperti playground. Hanya dipakai bila tidak ada
  /// ChargingScope — di aplikasi sungguhan harganya selalu dari backend.
  static KwhPrice priceFor(double kwh) {
    const ratePerKwh = 2466.78;
    const ppj = 2467;
    final energy = (kwh * ratePerKwh).round();

    return KwhPrice(
      kwh: kwh,
      rpPerKwh: ratePerKwh,
      rpPpj: ppj,
      rpTotal: energy + ppj,
    );
  }

  /// Order tiruan untuk mode offline, mengikuti bentuk
  /// `POST /transaction/push-order`.
  static Order orderFor(KwhPrice price) {
    return Order(
      orderId: 'DEMO-ORDER',
      // Sama dengan kode yang diterima Verifikasi Sesi saat offline,
      // supaya kode yang ditunjukkan memang bisa dipakai.
      sessionCode: Env.sessionPin,
      partnerReference: '81067',
      kwh: price.kwh,
      rpPerKwh: price.rpPerKwh,
      rpKwh: (price.kwh * price.rpPerKwh).round(),
      rpPpj: price.rpPpj,
      rpTotal: price.rpTotal,
    );
  }
}
