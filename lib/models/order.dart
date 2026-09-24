import 'kwh_price.dart';

/// Order yang sudah dibuat di backend, dari
/// `POST /transaction/push-order`.
///
/// Inilah sumber nomor referensi dan kode sesi — sebelumnya keduanya
/// dibangkitkan lokal untuk demo.
///
/// Rinciannya lebih lengkap daripada `POST /count-kwh`: ada [rpKwh],
/// biaya energi sebagai angka tersendiri, sehingga aplikasi tidak perlu
/// menurunkannya dari kWh dikali tarif.
class Order implements PriceBreakdown {
  const Order({
    required this.orderId,
    required this.sessionCode,
    required this.partnerReference,
    this.sessionExpiredAt,
    required this.kwh,
    required this.rpTotal,
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
    this.rpPerKwh = 0,
    this.rpKwh = 0,
    this.rpPpj = 0,
    this.rpPpn = 0,
    this.rpLayanan = 0,
    this.rpMaterai = 0,
    this.serviceFee = 0,
    this.idleFee = 0,
  });

  /// Identitas order, mis. "ADWTJU5D56QGZNXTTNOX9YZFTN". Baru setiap
  /// kali order dibuat.
  final String orderId;

  /// Kode yang diperlukan pengguna untuk mengakhiri sesinya, mis. "29".
  final String sessionCode;

  /// Nomor referensi yang ditampilkan pada detail transaksi.
  final String partnerReference;

  /// Batas waktu berlakunya order, dari `sessionExpiredTime`.
  ///
  /// Lewat dari ini backend membalas `21` untuk order tersebut — baik
  /// saat menagih maupun saat memulai pengisian.
  final DateTime? sessionExpiredAt;

  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;

  @override
  final double kwh;

  @override
  final double rpPerKwh;

  /// Biaya energi — kWh dikali tarif, dihitung backend.
  @override
  final int rpKwh;

  @override
  final int rpPpj;

  @override
  final int rpPpn;

  @override
  final int rpTotal;

  final int rpLayanan;
  final int rpMaterai;

  /// Field `serviceFee`, terpisah dari [rpLayanan] pada payload.
  final int serviceFee;

  final int idleFee;

  factory Order.fromJson(Map<String, dynamic>? json) {
    double number(String key) => (json?[key] as num?)?.toDouble() ?? 0;
    int rupiah(String key) => (json?[key] as num?)?.round() ?? 0;

    // Backend mengeja `chargeboxId` dengan b kecil di endpoint ini,
    // dan pernah memakai `sessionExpiredTime` sebelum menjadi
    // `sessionExpired`. Keduanya diterima supaya versi backend yang
    // berbeda tidak diam-diam kehilangan datanya.
    final id = json?['chargeBoxId'] ?? json?['chargeboxId'];
    final name = json?['chargeBoxName'] ?? json?['chargeboxName'];
    final expiry = json?['sessionExpired'] ?? json?['sessionExpiredTime'];

    return Order(
      orderId: json?['orderId'] as String? ?? '',
      sessionCode: json?['sessionCode'] as String? ?? '-',
      partnerReference: json?['partnerReference'] as String? ?? '-',
      sessionExpiredAt: switch (expiry) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
      chargeBoxId: id as String? ?? '',
      chargeBoxName: name as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      kwh: number('kwh'),
      rpPerKwh: number('rpPerKwh'),
      rpKwh: rupiah('rpKwh'),
      rpPpj: rupiah('rpPpj'),
      rpPpn: rupiah('rpPpn'),
      rpLayanan: rupiah('rpLayanan'),
      rpMaterai: rupiah('rpMaterai'),
      serviceFee: rupiah('serviceFee'),
      idleFee: rupiah('idleFee'),
      rpTotal: rupiah('rpTotal'),
    );
  }

  @override
  List<({String label, int amount})> get extraCharges => [
        for (final row in [
          (label: 'Biaya Layanan', amount: rpLayanan),
          (label: 'Biaya Jasa', amount: serviceFee),
          (label: 'Bea Materai', amount: rpMaterai),
          (label: 'Denda Idle', amount: idleFee),
        ])
          if (row.amount != 0) row,
      ];

  @override
  String toString() => 'Order($orderId, $kwh kWh, total $rpTotal)';
}
