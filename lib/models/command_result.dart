/// Hasil perintah `/start` dan `/stop`.
///
/// Bentuk nyata dari edge controller:
/// ```json
/// POST /start -> {"chargePointId":"SIM-456","connectorId":1,"state":"starting"}
/// POST /stop  -> {"chargePointId":"SIM-456","connectorId":1,
///                 "transactionId":1789648927,"state":"stopping"}
/// ```
///
/// Perhatikan `state` bernilai "starting", bukan "charging": controller
/// baru meneruskan perintah ke charger. Konfirmasi bahwa pengisian
/// benar-benar jalan datang dari `session` pada `GET /list`.
class CommandResult {
  const CommandResult({
    required this.chargePointId,
    required this.state,
    this.connectorId,
    this.transactionId,
  });

  final String chargePointId;

  /// "starting" untuk `/start`, "stopping" untuk `/stop`.
  final String state;

  /// Tidak dikirim balik bila permintaan tidak menyertakannya.
  final int? connectorId;

  /// Hanya terisi pada `/stop`.
  final int? transactionId;

  factory CommandResult.fromJson(Map<String, dynamic>? json) {
    return CommandResult(
      chargePointId: json?['chargePointId'] as String? ?? '',
      state: json?['state'] as String? ?? '',
      connectorId: (json?['connectorId'] as num?)?.toInt(),
      transactionId: (json?['transactionId'] as num?)?.toInt(),
    );
  }

  bool get isStarting => state == 'starting';
  bool get isStopping => state == 'stopping';

  @override
  String toString() => 'CommandResult($chargePointId'
      '${connectorId == null ? '' : '/$connectorId'} state=$state'
      '${transactionId == null ? '' : ' tx=$transactionId'})';
}
