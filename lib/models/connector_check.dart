import 'ocpp_status.dart';

/// Jawaban `POST /check-status-connector`.
///
/// ```json
/// {
///   "chargeBoxId": "CB-SMR-01",
///   "chargeboxName": "Kempower Satellite 200 kW",
///   "connectorName": "Gun 1",
///   "connectorId": "1",
///   "connectorStatus": "Available"
/// }
/// ```
///
/// Dipakai halaman Hubungkan Konektor untuk menunggu kabel tercolok.
class ConnectorCheck {
  const ConnectorCheck({
    this.status = '',
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
  });

  /// `connectorStatus` apa adanya, mis. "Preparing". Kosakatanya ada di
  /// [OcppStatus].
  final String status;

  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;

  factory ConnectorCheck.fromJson(Map<String, dynamic>? json) {
    // Ejaan `chargeboxId`/`chargeboxName` dengan b kecil dipakai
    // sebagian endpoint; keduanya diterima supaya versi backend yang
    // berbeda tidak diam-diam kehilangan datanya.
    final id = json?['chargeBoxId'] ?? json?['chargeboxId'];
    final name = json?['chargeBoxName'] ?? json?['chargeboxName'];

    return ConnectorCheck(
      status: json?['connectorStatus'] as String? ?? '',
      chargeBoxId: id as String? ?? '',
      chargeBoxName: name as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
    );
  }

  /// Kabelnya sudah terpasang ke kendaraan.
  bool get isPluggedIn => OcppStatus.isPluggedIn(status);

  /// Charger sedang tidak bisa dipakai sama sekali.
  bool get isBroken => OcppStatus.isBroken(status);

  @override
  String toString() => 'ConnectorCheck($chargeBoxId/$connectorId, $status)';
}
