/// Tahap booking konektor pada `POST /booked-connector`.
///
/// Konektor dikunci atas nama satu pengguna sejak ia memilih nozzle,
/// lalu tahapnya dinaikkan seiring alur pembelian sehingga backend tahu
/// sejauh mana prosesnya.
enum BookingStage {
  /// R0 — nozzle baru dipilih. Inilah yang mengunci konektor supaya
  /// tidak bisa diambil orang lain.
  selected('R0'),

  /// R1 — order sedang dibuat.
  ordering('R1'),

  /// R2 — pembayaran dikonfirmasi.
  paid('R2'),

  /// R3 — pengisian dimulai.
  starting('R3');

  const BookingStage(this.code);

  /// Nilai yang dikirim pada field `connectorStatus`.
  final String code;
}

/// Jawaban `POST /booked-connector`.
///
/// ```json
/// {
///   "chargeBoxId": "CB-SMR-01",
///   "chargeBoxName": "Kempower Satellite 200 kW",
///   "connectorName": "Gun 1",
///   "connectorId": "1",
///   "connectorStatus": "R0",
///   "status": true
/// }
/// ```
class BookingResult {
  const BookingResult({
    required this.accepted,
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
    this.connectorStatus = '',
  });

  /// Field `status`: konektornya bersedia (true) atau tidak (false).
  ///
  /// Hanya bermakna pada [BookingStage.selected] — di situ false berarti
  /// konektornya sudah diambil orang lain dan alur tidak boleh lanjut.
  ///
  /// Pada tahap berikutnya nilainya selalu false, dan itu wajar:
  /// bookingnya sudah dipegang pengguna ini, jadi konektornya memang
  /// tidak lagi bersedia. Permintaannya tidak membawa identitas
  /// pemesan, sehingga backend tidak bisa membedakan "diambil Anda" dari
  /// "diambil orang lain". Karena itu R1–R3 tidak pernah dipakai untuk
  /// menggagalkan alur.
  final bool accepted;

  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;

  /// Kode tahap yang dikirim balik, mis. "R0".
  final String connectorStatus;

  factory BookingResult.fromJson(Map<String, dynamic>? json) {
    return BookingResult(
      accepted: json?['status'] as bool? ?? false,
      chargeBoxId: json?['chargeBoxId'] as String? ?? '',
      chargeBoxName: json?['chargeBoxName'] as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      connectorStatus: json?['connectorStatus'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'BookingResult($chargeBoxId/$connectorId $connectorStatus '
      'accepted=$accepted)';
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
