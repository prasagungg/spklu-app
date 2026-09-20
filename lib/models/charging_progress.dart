import 'backend_status.dart';

/// Kemajuan pengisian satu order, dari
/// `POST /transaction/charging/ongoing-kwh`.
///
/// ```json
/// {
///   "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID",
///   "chargeBoxId": "CB-SMR-01",
///   "chargeBoxName": "Kempower Satellite 200 kW",
///   "connectorName": "Gun 2",
///   "orderKwh": 10, "charged": 0, "remaining": 10,
///   "status": 2, "lastSoc": null, "firstSoc": null,
///   "power": 0, "chargeDurationS": 0, "chargeDurationM": 0,
///   "estRemainingTime": 0, "powerActiveImport": 0,
///   "estimatedCharged": 0
/// }
/// ```
///
/// Berbeda dari `GET /progress` yang lama, [charged] sudah dalam **kWh**
/// — bukan Wh — jadi angkanya dipakai apa adanya.
class ChargingProgress {
  const ChargingProgress({
    this.orderId = '',
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorName = '',
    this.orderKwh = 0,
    this.charged = 0,
    this.remaining = 0,
    this.statusCode,
    this.firstSoc,
    this.lastSoc,
    this.power = 0,
    this.powerActiveImport = 0,
    this.estimatedCharged = 0,
    this.chargeDurationS = 0,
    this.chargeDurationM = 0,
    this.estRemainingTime = 0,
  });

  final String orderId;
  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorName;

  /// kWh yang dipesan.
  final double orderKwh;

  /// kWh yang sudah tersalur.
  final double charged;

  /// Sisa kWh yang belum tersalur.
  final double remaining;

  /// Angka status, memakai kosakata yang sama dengan konektor — lihat
  /// [BackendStatus].
  final int? statusCode;

  /// Daya baterai kendaraan saat mulai dan terakhir dibaca, dalam
  /// persen. Null bila charger tidak melaporkannya.
  final double? firstSoc;
  final double? lastSoc;

  final double power;
  final double powerActiveImport;
  final double estimatedCharged;

  final int chargeDurationS;
  final int chargeDurationM;

  /// Perkiraan sisa waktu, dalam menit.
  final int estRemainingTime;

  factory ChargingProgress.fromJson(Map<String, dynamic>? json) {
    double number(String key) => (json?[key] as num?)?.toDouble() ?? 0;
    double? maybeNumber(String key) => (json?[key] as num?)?.toDouble();
    int whole(String key) => (json?[key] as num?)?.round() ?? 0;

    return ChargingProgress(
      orderId: json?['orderId'] as String? ?? '',
      chargeBoxId: json?['chargeBoxId'] as String? ?? '',
      chargeBoxName: json?['chargeBoxName'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      orderKwh: number('orderKwh'),
      charged: number('charged'),
      remaining: number('remaining'),
      statusCode: BackendStatus.parse(json?['status']),
      firstSoc: maybeNumber('firstSoc'),
      lastSoc: maybeNumber('lastSoc'),
      power: number('power'),
      powerActiveImport: number('powerActiveImport'),
      estimatedCharged: number('estimatedCharged'),
      chargeDurationS: whole('chargeDurationS'),
      chargeDurationM: whole('chargeDurationM'),
      estRemainingTime: whole('estRemainingTime'),
    );
  }

  /// Sedang mengisi.
  bool get isCharging => statusCode == BackendStatus.charging;

  /// Pengisian sudah selesai di sisi charger.
  bool get isFinished => statusCode == BackendStatus.finished;

  Duration get duration => Duration(seconds: chargeDurationS);

  @override
  String toString() => 'ChargingProgress($orderId, $charged/$orderKwh kWh, '
      'status $statusCode)';
}
