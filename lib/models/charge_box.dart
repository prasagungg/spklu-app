import 'backend_status.dart';
import 'connector.dart';

/// Satu charge box dari `POST /list-chargerbox`.
///
/// ```json
/// {
///   "chargeboxId": "CB-SMR-01",
///   "merek": "Kempower",
///   "daya": "200 kW",
///   "isActive": true,
///   "namaChargebox": "Kempower Satellite 200 kW",
///   "connectorTotal": 2,
///   "connectors": [ … ]
/// }
/// ```
///
/// Ejaan `chargeboxId`/`namaChargebox` sempat berupa
/// `chargeBoxId`/`namaChargeBox`. Keduanya diterima supaya versi
/// backend yang berbeda tidak memecahkan aplikasi.
class ChargeBox {
  const ChargeBox({
    required this.number,
    required this.id,
    required this.connectors,
    this.displayName,
    this.merek = '',
    this.daya = '',
    this.isActive = true,
    this.connectorTotal,
    this.statusCode,
  });

  /// Urutan tampil (1, 2, 3...). Backend tidak mengirim nomor parkir,
  /// jadi dipakai posisi di daftar.
  final int number;

  /// `chargeboxId`, mis. "CB-SMR-01". Dipakai apa adanya oleh seluruh
  /// endpoint yang menyebut charge box.
  final String id;

  /// `namaChargebox`, mis. "Kempower Satellite 200 kW".
  final String? displayName;

  /// `merek`, mis. "Kempower".
  final String merek;

  /// `daya`, mis. "200 kW". Teks apa adanya, bukan angka.
  final String daya;

  /// `isActive` — charge box yang dimatikan tidak bisa dipakai.
  final bool isActive;

  /// `connectorTotal` dari backend. Dipakai bila daftar konektornya
  /// ternyata tidak lengkap.
  final int? connectorTotal;

  /// Angka `status` apa adanya, dari versi backend yang masih
  /// mengirimnya.
  final int? statusCode;

  final List<Connector> connectors;

  factory ChargeBox.fromJson(Map<String, dynamic> json, {required int number}) {
    final rawConnectors = json['connectors'];
    final id = json['chargeboxId'] ?? json['chargeBoxId'];
    final name = json['namaChargebox'] ?? json['namaChargeBox'];

    return ChargeBox(
      number: number,
      id: id as String? ?? '-',
      displayName: name as String?,
      merek: json['merek'] as String? ?? '',
      daya: json['daya'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      connectorTotal: (json['connectorTotal'] as num?)?.toInt(),
      statusCode: BackendStatus.parse(json['status']),
      connectors: rawConnectors is List
          ? rawConnectors
                .whereType<Map<String, dynamic>>()
                .map(Connector.fromJson)
                .toList()
          : const [],
    );
  }

  String get badge => number.toString().padLeft(2, '0');

  String get connectorLabel =>
      '${connectorTotal ?? connectors.length} Konektor';

  /// Jatuh ke id charge box bila tidak ada nama tampilan.
  String get name => displayName ?? id;

  /// Bisa dipilih selama charge box-nya hidup dan ada minimal satu
  /// konektor yang statusnya dikenal.
  ///
  /// Angka `status` milik charge box sengaja tidak ikut: keempat nilai
  /// yang terdokumentasi menggambarkan keadaan sesi pada konektor, dan
  /// memakainya di sini berisiko mematikan kartu yang sebenarnya sedang
  /// melayani pengisian. `isActive` adalah sinyal yang tepat untuk itu.
  bool get isAvailable => isActive && connectors.any((c) => c.isSelectable);
}
