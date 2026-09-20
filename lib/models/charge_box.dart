import 'backend_status.dart';
import 'connector.dart';

/// Satu charge box dari `POST /list-chargerbox`.
///
/// ```json
/// {
///   "chargeBoxId": "CB-SMR-01",
///   "merek": "Kempower",
///   "status": 1,
///   "namaChargeBox": "Kempower Satellite 200 kW",
///   "connectors": [ … ]
/// }
/// ```
class ChargeBox {
  const ChargeBox({
    required this.number,
    required this.id,
    required this.connectors,
    this.displayName,
    this.merek = '',
    this.statusCode,
  });

  /// Urutan tampil (1, 2, 3...). Backend tidak mengirim nomor parkir,
  /// jadi dipakai posisi di daftar.
  final int number;

  /// `chargeBoxId`, mis. "CB-SMR-01". Dipakai apa adanya oleh `/start`,
  /// `/stop`, dan `/progress`.
  final String id;

  /// `namaChargeBox`, mis. "Kempower Satellite 200 kW".
  final String? displayName;

  /// `merek`, mis. "Kempower".
  final String merek;

  /// Angka `status` apa adanya dari backend.
  final int? statusCode;

  final List<Connector> connectors;

  factory ChargeBox.fromJson(Map<String, dynamic> json, {required int number}) {
    final rawConnectors = json['connectors'];

    return ChargeBox(
      number: number,
      id: json['chargeBoxId'] as String? ?? '-',
      displayName: json['namaChargeBox'] as String?,
      merek: json['merek'] as String? ?? '',
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

  String get connectorLabel => '${connectors.length} Konektor';

  /// Jatuh ke id charge box bila tidak ada nama tampilan.
  String get name => displayName ?? id;

  /// Bisa dipilih selama ada minimal satu konektor yang statusnya
  /// dikenal.
  ///
  /// Sengaja tidak menyertakan [statusCode] milik charge box: keempat
  /// angka yang terdokumentasi menggambarkan keadaan satu sesi pada
  /// konektor, dan belum ketahui apakah kosakata yang sama dipakai di
  /// tingkat charge box. Memakainya di sini berisiko mematikan kartu
  /// yang sebenarnya sedang melayani pengisian.
  bool get isAvailable => connectors.any((c) => c.isSelectable);
}
