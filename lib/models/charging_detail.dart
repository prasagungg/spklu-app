import 'backend_status.dart';

/// Rincian akhir satu order, dari `POST /transaction/charging/detail`.
///
/// ```json
/// {
///   "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS",
///   "chargeboxId": "ACMP_UAT", "chargeboxName": "ACMP UAT",
///   "connectorName": "AC 22 kW", "connectorId": "2",
///   "status": 2, "kwhPesan": 10, "kwhPakai": 0, "sisaKwh": 10,
///   "rpPesan": 18775, "rpPakai": 0, "rpSisa": 18775,
///   "hargaKwh": 1710, "chargeDuration": "0",
///   "chargeDurationInMinutes": "0",
///   "idleFee": 0, "serviceFee": 1332.2,
///   "firstSoc": null, "lastSoc": null,
///   "tglCatat": "2026-09-24T04:08:39Z"
/// }
/// ```
///
/// Inilah sumber angka halaman "Pengisian Selesai". Sebelumnya aplikasi
/// menghitung sendiri pemakaian dan kembaliannya dari nominal yang
/// dibayar — hasilnya tidak pernah bisa dijamin sama dengan pembukuan
/// backend. Sekarang keempat angkanya diambil apa adanya.
///
/// Beberapa field dikirim sebagai teks (`chargeDuration`) atau null
/// (`rpMaterai`, `firstSoc`), jadi penguraiannya sengaja longgar.
class ChargingDetail {
  const ChargingDetail({
    this.orderId = '',
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
    this.sessionCode = '',
    this.statusCode,
    this.orderedKwh = 0,
    this.usedKwh = 0,
    this.remainingKwh = 0,
    this.paidAmount = 0,
    this.usageAmount = 0,
    this.refundAmount = 0,
    this.pricePerKwh = 0,
    this.idleFee = 0,
    this.serviceFee = 0,
    this.firstSoc,
    this.lastSoc,
    this.duration = Duration.zero,
    this.recordedAt,
  });

  final String orderId;
  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;
  final String sessionCode;

  /// Tahap transaksinya — lihat [BackendStatus].
  final int? statusCode;

  /// `kwhPesan` — yang dibeli.
  final double orderedKwh;

  /// `kwhPakai` — yang benar-benar tersalur.
  final double usedKwh;

  /// `sisaKwh` — yang dibeli tapi tidak terpakai.
  final double remainingKwh;

  /// `rpPesan` — yang dibayar di awal.
  final num paidAmount;

  /// `rpPakai` — nilai energi yang terpakai.
  final num usageAmount;

  /// `rpSisa` — yang dikembalikan.
  final num refundAmount;

  /// `hargaKwh` — tarif yang berlaku pada transaksi ini.
  final double pricePerKwh;

  final num idleFee;
  final num serviceFee;

  /// Daya baterai kendaraan, dalam persen. Null bila charger tidak
  /// melaporkannya.
  final double? firstSoc;
  final double? lastSoc;

  /// Lama pengisian, dari `chargeDuration` (detik).
  final Duration duration;

  /// `tglCatat`.
  final DateTime? recordedAt;

  factory ChargingDetail.fromJson(Map<String, dynamic>? json) {
    // `chargeDuration` dikirim sebagai teks ("0"), sebagian angka
    // lain sebagai null. Keduanya dibaca lewat satu jalan.
    double number(String key) => switch (json?[key]) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };
    double? maybeNumber(String key) => switch (json?[key]) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    // Tanpa pembulatan: rupiah dari backend bisa pecahan.
    num rupiah(String key) => number(key);

    return ChargingDetail(
      orderId: json?['orderId'] as String? ?? '',
      chargeBoxId:
          (json?['chargeboxId'] ?? json?['chargeBoxId']) as String? ?? '',
      chargeBoxName:
          (json?['chargeboxName'] ?? json?['chargeBoxName']) as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      connectorName: json?['connectorName'] as String? ?? '',
      sessionCode: json?['sessionCode'] as String? ?? '',
      statusCode: BackendStatus.parse(json?['status']),
      orderedKwh: number('kwhPesan'),
      usedKwh: number('kwhPakai'),
      remainingKwh: number('sisaKwh'),
      paidAmount: rupiah('rpPesan'),
      usageAmount: rupiah('rpPakai'),
      refundAmount: rupiah('rpSisa'),
      pricePerKwh: number('hargaKwh'),
      idleFee: rupiah('idleFee'),
      serviceFee: rupiah('serviceFee'),
      firstSoc: maybeNumber('firstSoc'),
      lastSoc: maybeNumber('lastSoc'),
      duration: Duration(seconds: number('chargeDuration').round()),
      recordedAt: switch (json?['tglCatat']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  String toString() =>
      'ChargingDetail($orderId, $usedKwh/$orderedKwh kWh, '
      'bayar $paidAmount, pakai $usageAmount, sisa $refundAmount)';
}
