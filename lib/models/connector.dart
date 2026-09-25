import 'backend_status.dart';
import 'connector_status_code.dart';

/// Status konektor yang dipakai UI, sejalan dengan angka `status` dari
/// backend (lihat [ConnectorStatusCode]).
///
/// - [reserved]        Sudah dipesan; belum sampai pembelian.
/// - [available]       Tersedia, bisa langsung dibeli.
/// - [inUse]           Sedang digunakan.
/// - [awaitingPayment] Menunggu pembayaran; ordernya sudah dibuat.
/// - [unavailable]     Tidak tersedia, termasuk angka yang tak dikenal.
///
/// Semua kecuali [available] berarti konektornya sudah diklaim orang
/// lain, jadi pengguna harus membuktikan kepemilikan sesi lebih dulu.
enum ConnectorStatus {
  reserved,
  available,
  inUse,
  awaitingPayment,
  unavailable,
}

/// Satu konektor pada charge box, dari `POST /list-chargerbox`.
///
/// ```json
/// {
///   "connectorId": "1",
///   "chargeBoxId": "CB-SMR-01",
///   "status": 1,
///   "namaKonektor": "Gun 1",
///   "typeConnector": "CCS2",
///   "connectorTypeCurrent": "DC",
///   "estimationAvailable": null
/// }
/// ```
class Connector {
  const Connector({
    required this.id,
    required this.status,
    this.statusCode,
    this.displayName,
    this.typeConnector = '',
    this.currentType = '',
    this.estimatedMinutes,
  });

  /// Nomor konektor. Backend mengirimnya sebagai teks (`"1"`), tetapi
  /// `/start`, `/stop`, dan `/progress` menerimanya sebagai angka, jadi
  /// diurai di sini sekali saja.
  final int id;

  final ConnectorStatus status;

  /// Angka `status` apa adanya dari backend — disimpan supaya bisa
  /// ditampilkan saat konektornya tidak bisa dipakai.
  final int? statusCode;

  /// `namaKonektor`, mis. "Gun 1".
  final String? displayName;

  /// `typeConnector`, mis. "CCS2".
  final String typeConnector;

  /// `connectorTypeCurrent`, mis. "DC" atau "AC".
  final String currentType;

  /// `estimationAvailable` — perkiraan menit sampai konektor bebas.
  /// Null bila backend tidak mengirimnya.
  final int? estimatedMinutes;

  factory Connector.fromJson(Map<String, dynamic> json) {
    final statusCode = BackendStatus.parse(json['status']);

    return Connector(
      id: BackendStatus.parse(json['connectorId']) ?? 0,
      statusCode: statusCode,
      status: mapStatus(statusCode),
      displayName: json['namaKonektor'] as String?,
      typeConnector: json['typeConnector'] as String? ?? '',
      currentType: json['connectorTypeCurrent'] as String? ?? '',
      // `estimatimationAvailable` ejaan backend sekarang; ejaan tanpa
      // salah ketiknya tetap diterima.
      estimatedMinutes: BackendStatus.parse(
        json['estimatimationAvailable'] ?? json['estimationAvailable'],
      ),
    );
  }

  /// Satu-satunya tempat angka status konektor diterjemahkan.
  ///
  /// Status yang hilang diperlakukan seperti bebas — lihat
  /// [ConnectorStatusCode.isUsable]. Angka `4` dan angka yang tidak
  /// dikenal sama-sama jatuh ke [ConnectorStatus.unavailable].
  static ConnectorStatus mapStatus(int? code) => switch (code) {
    null || ConnectorStatusCode.available => ConnectorStatus.available,
    ConnectorStatusCode.reserved => ConnectorStatus.reserved,
    ConnectorStatusCode.inUse => ConnectorStatus.inUse,
    ConnectorStatusCode.awaitingPayment => ConnectorStatus.awaitingPayment,
    _ => ConnectorStatus.unavailable,
  };

  /// Tersedia untuk siapa saja.
  bool get isAvailable => status == ConnectorStatus.available;

  /// Sudah dipesan orang lain, belum sampai pembelian.
  bool get isReserved => status == ConnectorStatus.reserved;

  /// Sedang digunakan.
  bool get isInUse => status == ConnectorStatus.inUse;

  /// Ordernya sudah dibuat, tagihannya belum dibayar.
  bool get isAwaitingPayment => status == ConnectorStatus.awaitingPayment;

  /// Boleh ditekan pengguna. Keadaan yang dikenal bisa ditekan — yang
  /// selain [available] mengharuskan verifikasi kode sesi lebih dulu.
  /// Yang mati hanya "tidak tersedia", termasuk angka yang tak dikenal.
  bool get isSelectable => status != ConnectorStatus.unavailable;

  /// Salinan dengan status hasil `POST /detail-chargerbox`.
  ///
  /// Daftar charge box tidak memperlihatkan status sebenarnya, jadi
  /// nilai dari daftar ditimpa begitu jawabannya datang.
  Connector withStatusCode(int? code) => Connector(
    id: id,
    status: mapStatus(code),
    statusCode: code,
    displayName: displayName,
    typeConnector: typeConnector,
    currentType: currentType,
    estimatedMinutes: estimatedMinutes,
  );

  /// Jatuh ke nomor konektor bila backend tidak mengirim namanya.
  String get name => displayName ?? 'Konektor $id';

  /// "CCS2 · DC". Kosong bila backend tidak mengirim keduanya.
  String get typeLabel =>
      [typeConnector, currentType].where((p) => p.isNotEmpty).join(' · ');

  /// "CCS2 - 200 kW DC", memakai daya charge box tempat konektor ini
  /// berada — dayanya milik charge box, bukan konektornya.
  ///
  /// Jatuh ke [typeLabel] bila dayanya tidak diketahui, dan ke [name]
  /// bila tipenya pun tidak dikirim.
  String describeWith(String daya) {
    if (daya.isEmpty) return typeLabel.isEmpty ? name : typeLabel;
    if (typeConnector.isEmpty) return daya;

    return [
      typeConnector,
      '-',
      daya,
      currentType,
    ].where((p) => p.isNotEmpty).join(' ');
  }
}
