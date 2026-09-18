/// Isi `session` pada konektor dari `GET /list`.
///
/// Contoh nyata dari edge controller:
/// Bentuk yang sama juga dikembalikan `GET /progress`.
///
/// Sedang mengisi:
/// ```json
/// {
///   "chargePointId": "SIM-456", "connectorId": 2,
///   "transactionId": 1789648926, "idTag": "REMOTE",
///   "state": "charging", "connectorStatus": "Charging",
///   "percent": 20.1, "energyWh": 24, "powerW": 12330,
///   "durationSeconds": 6, "stoppedAt": null,
///   "updatedAt": "2026-09-17T20:13:51.943093729+07:00"
/// }
/// ```
///
/// Backend mengirim `energyWh` dan `energyKwh` sekaligus; yang kedua
/// dipakai apa adanya bila ada.
///
/// Setelah selesai — `powerW` menjadi null dan muncul `stopReason`:
/// ```json
/// {
///   "state": "finished", "connectorStatus": "Preparing",
///   "percent": 55.5, "energyWh": 207, "powerW": null,
///   "durationSeconds": 59, "stopReason": "Remote",
///   "stoppedAt": "2026-09-17T20:58:35.135618667+07:00"
/// }
/// ```
class SessionInfo {
  const SessionInfo({
    required this.chargePointId,
    required this.connectorId,
    required this.transactionId,
    required this.idTag,
    required this.state,
    required this.connectorStatus,
    required this.percent,
    required this.energyWh,
    required this.energyKwh,
    required this.powerW,
    required this.durationSeconds,
    this.stopReason,
    this.stoppedAt,
    this.updatedAt,
  });

  final String chargePointId;
  final int connectorId;
  final int transactionId;
  final String idTag;

  /// "starting", "charging", "stopping", ...
  final String state;

  final String connectorStatus;
  final double percent;
  final int energyWh;

  /// Energi dalam kWh. Backend mengirimnya langsung; bila field itu
  /// tidak ada, dihitung dari [energyWh].
  final double energyKwh;

  final int powerW;
  final int durationSeconds;

  /// Hanya terisi setelah sesi berhenti, mis. "Remote".
  final String? stopReason;

  final DateTime? stoppedAt;
  final DateTime? updatedAt;

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      chargePointId: json['chargePointId'] as String? ?? '',
      connectorId: (json['connectorId'] as num?)?.toInt() ?? 0,
      transactionId: (json['transactionId'] as num?)?.toInt() ?? 0,
      idTag: json['idTag'] as String? ?? '',
      state: json['state'] as String? ?? '',
      connectorStatus: json['connectorStatus'] as String? ?? '',
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      energyWh: (json['energyWh'] as num?)?.toInt() ?? 0,
      energyKwh: (json['energyKwh'] as num?)?.toDouble() ??
          ((json['energyWh'] as num?)?.toDouble() ?? 0) / 1000,
      powerW: (json['powerW'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      stopReason: json['stopReason'] as String?,
      stoppedAt: _parseDate(json['stoppedAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  double get powerKw => powerW / 1000;

  Duration get duration => Duration(seconds: durationSeconds);

  bool get isCharging => state == 'charging';

  /// Sesi sudah berhenti di sisi charger.
  ///
  /// `state` bernilai "finished" dan `stoppedAt` terisi; `powerW` ikut
  /// menjadi null karena tidak ada daya yang mengalir lagi.
  bool get isFinished => state == 'finished' || stoppedAt != null;
}
