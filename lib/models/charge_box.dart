import 'connector.dart';

/// Satu charge point dari `GET /api/list`.
class ChargeBox {
  const ChargeBox({
    required this.number,
    required this.id,
    required this.connectors,
    this.displayName,
    this.vendor = '',
    this.model = '',
    this.serialNumber = '',
    this.firmwareVersion = '',
    this.connectedAt,
    this.lastHeartbeat,
  });

  /// Urutan tampil (1, 2, 3...). Backend tidak mengirim nomor parkir,
  /// jadi dipakai posisi di daftar.
  final int number;

  /// Identitas charge point, mis. "SIM-123".
  final String id;

  /// Nama tampilan. Backend belum punya field nama, jadi hanya terisi
  /// pada data dummy.
  final String? displayName;

  final String vendor;
  final String model;
  final String serialNumber;
  final String firmwareVersion;
  final DateTime? connectedAt;
  final DateTime? lastHeartbeat;
  final List<Connector> connectors;

  factory ChargeBox.fromJson(Map<String, dynamic> json, {required int number}) {
    final rawConnectors = json['connectors'];

    return ChargeBox(
      number: number,
      id: json['id'] as String? ?? '-',
      vendor: json['vendor'] as String? ?? '',
      model: json['model'] as String? ?? '',
      serialNumber: json['serialNumber'] as String? ?? '',
      firmwareVersion: json['firmwareVersion'] as String? ?? '',
      connectedAt: _parseDate(json['connectedAt']),
      lastHeartbeat: _parseDate(json['lastHeartbeat']),
      connectors: rawConnectors is List
          ? rawConnectors
              .whereType<Map<String, dynamic>>()
              .map(Connector.fromJson)
              .toList()
          : const [],
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  String get badge => number.toString().padLeft(2, '0');

  String get connectorLabel => '${connectors.length} Konektor';

  /// Jatuh ke id charge point bila tidak ada nama tampilan.
  String get name => displayName ?? id;

  /// Bisa dipilih selama ada minimal satu konektor tanpa transaksi
  /// berjalan — baik yang masih "Available" maupun yang sudah
  /// "Preparing" (kabel tercolok, belum mengisi).
  bool get isAvailable => connectors.any((c) => c.isSelectable);
}
