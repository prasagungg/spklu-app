import 'backend_status.dart';

/// Jawaban `POST /manage-sessioncode`.
///
/// ```json
/// {
///   "chargeboxId": "delta_sensi",
///   "chargeboxName": "Delta DC Wallbox",
///   "connectorName": "AC TYPE 2 - 7.0",
///   "connectorId": "1",
///   "sessionCode": "29",
///   "statusProcess": 1
/// }
/// ```
///
/// Dua gunanya: membuktikan kode sesi yang diketik pengguna memang
/// milik sesi itu, dan — karena [statusProcess] ikut dikirim — memantau
/// apakah konektornya sudah tercolok.
class SessionCheck {
  const SessionCheck({
    this.orderId = '',
    this.reservationId = '',
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
    this.sessionCode = '',
    this.statusProcess,
  });

  /// Order milik sesi itu. Dipakai halaman berikutnya untuk memantau
  /// dan menghentikan pengisian — semua perintah pengisian berkunci
  /// order, sedangkan daftar charge box tidak membawanya.
  final String orderId;

  /// Pemesanan milik sesi itu, bila backend menyertakannya. Diperlukan
  /// `push-order` bagi sesi yang belum sampai tahap pembayaran.
  final String reservationId;

  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;
  final String sessionCode;

  /// Tahap proses, memakai kosakata angka yang sama dengan status
  /// konektor — lihat [BackendStatus].
  final int? statusProcess;

  factory SessionCheck.fromJson(Map<String, dynamic>? json) {
    // Ejaan `chargeboxId` dengan b kecil pernah dipakai endpoint ini
    // sebelum dirapikan jadi `chargeBoxId`. Keduanya tetap diterima
    // supaya versi backend yang berbeda tidak memecahkan aplikasi.
    final id = json?['chargeboxId'] ?? json?['chargeBoxId'];
    final name = json?['chargeboxName'] ?? json?['chargeBoxName'];

    return SessionCheck(
      orderId: json?['orderId'] as String? ?? '',
      reservationId: json?['reservationId'] as String? ?? '',
      chargeBoxId: id as String? ?? '',
      chargeBoxName: name as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      sessionCode: json?['sessionCode'] as String? ?? '',
      statusProcess: BackendStatus.parse(json?['statusProcess']),
    );
  }

  /// Konektornya sudah tercolok ke kendaraan.
  ///
  /// Selama backend masih meminta konektor dihubungkan nilainya
  /// [BackendStatus.awaitingConnector]; begitu berpindah ke tahap
  /// pengisian, kabelnya sudah terpasang.
  ///
  /// Sengaja mencocokkan nilai yang dikenal, bukan "lebih besar dari".
  /// Angka yang tidak dikenal berarti aplikasi tidak tahu keadaannya,
  /// dan menebaknya sebagai tercolok akan mengirim perintah start yang
  /// pasti ditolak charger.
  bool get isPluggedIn =>
      statusProcess == BackendStatus.charging ||
      statusProcess == BackendStatus.finished;

  @override
  String toString() =>
      'SessionCheck($orderId, $chargeBoxId/$connectorId, '
      'kode $sessionCode, statusProcess $statusProcess)';
}
