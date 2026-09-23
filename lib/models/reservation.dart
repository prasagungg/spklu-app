/// Pemesanan konektor, dari `POST /booked-connector`.
///
/// ```json
/// {
///   "chargeBoxId": "CB-SMR-01",
///   "chargeboxName": "Kempower Satellite 200 kW",
///   "connectorName": "Gun 1",
///   "connectorId": "1",
///   "connectorStatus": "R0",
///   "sessionExpired": "2026-09-23T09:56:04Z",
///   "reservationId": "U33tiFAl0Yj5TkCQyoUmU",
///   "sessionCode": "05",
///   "status": true
/// }
/// ```
///
/// Inilah sumber kode sesi — sebelumnya datang dari `push-order`, dan
/// sebelum itu lagi dikarang aplikasi. Pengguna mendapatkannya sejak ia
/// memilih nozzle, jauh sebelum membayar.
class Reservation {
  const Reservation({
    required this.accepted,
    this.reservationId = '',
    this.sessionCode = '',
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
    this.connectorStatus = '',
    this.expiredAt,
  });

  /// Field `status`: konektornya bersedia (true) atau tidak (false).
  ///
  /// False berarti sudah diambil orang lain dan alur tidak boleh lanjut.
  final bool accepted;

  /// Identitas pemesanan. Wajib dibawa `push-order` dan
  /// `cancelled-connector`.
  final String reservationId;

  /// Kode yang diperlukan pengguna untuk kembali ke sesinya.
  final String sessionCode;

  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;

  /// Tahap yang ditetapkan backend sendiri, mis. "R0". Aplikasi tidak
  /// pernah mengirimkannya.
  final String connectorStatus;

  /// Batas waktu pemesanan, dari `sessionExpired`. Lewat dari ini
  /// backend melepas konektornya.
  final DateTime? expiredAt;

  factory Reservation.fromJson(Map<String, dynamic>? json) {
    final name = json?['chargeboxName'] ?? json?['chargeBoxName'];

    return Reservation(
      accepted: json?['status'] as bool? ?? false,
      reservationId: json?['reservationId'] as String? ?? '',
      sessionCode: json?['sessionCode'] as String? ?? '',
      chargeBoxId: (json?['chargeBoxId'] ?? json?['chargeboxId']) as String? ??
          '',
      chargeBoxName: name as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      connectorStatus: json?['connectorStatus'] as String? ?? '',
      expiredAt: switch (json?['sessionExpired']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  String toString() => 'Reservation($reservationId, kode $sessionCode, '
      '$connectorStatus, accepted=$accepted)';
}

/// Jawaban `POST /cancelled-connector`.
///
/// ```json
/// {
///   "chargeBoxId": "CB-SMR-01",
///   "chargeBoxName": "Kempower Satellite 200 kW",
///   "connectorName": "Gun 1",
///   "connectorId": "1",
///   "statusMessage": "Connector Cancelled"
/// }
/// ```
///
/// Tidak ada field `status`: pembatalan selalu berhasil selama
/// konektornya dikenal, termasuk untuk konektor yang memang sedang
/// tidak dibooking.
class CancellationResult {
  const CancellationResult({
    this.chargeBoxId = '',
    this.connectorId = '',
    this.connectorName = '',
    this.statusMessage = '',
  });

  final String chargeBoxId;
  final String connectorId;
  final String connectorName;

  /// Mis. "Connector Cancelled".
  final String statusMessage;

  factory CancellationResult.fromJson(Map<String, dynamic>? json) {
    return CancellationResult(
      chargeBoxId: json?['chargeBoxId'] as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      statusMessage: json?['statusMessage'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'CancellationResult($chargeBoxId/$connectorId $statusMessage)';
}
