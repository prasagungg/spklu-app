/// Rincian satu transaksi di riwayat, dari
/// `POST /transaction/detail-history-transaction`.
///
/// ```json
/// {
///   "chargeboxId": "ACMP_UAT", "chargeboxName": "ACMP UAT",
///   "connectorId": 2, "connectorName": "AC 22 kW",
///   "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS",
///   "namaSpklu": "SPKLU PLN PUSAT",
///   "pspId": "EM-BNI", "cardNumber": "012••••••••••345",
///   "status": 0, "tglCatat": "2026-09-24T04:08:39Z",
///   "kwhPesan": 10, "kwhPakai": 0, "sisaKwh": null,
///   "rpPesan": 18775, "rpPakai": 0, "rpSisa": null,
///   "hargaKwh": 1710, "rpLayanan": 1332.2, "idleFee": 0
/// }
/// ```
///
/// Dua hal yang membedakannya dari `charging/detail`: amplopnya memakai
/// `response_code`/`response_message`, dan **nomor kartunya sudah
/// disamarkan backend** ("012••••••••••345") — jadi ditampilkan apa
/// adanya, tidak disamarkan ulang.
///
/// Banyak field dikirim null pada transaksi yang tidak sampai selesai,
/// jadi penguraiannya longgar dan angka yang tidak ada bernilai nol.
class TransactionDetail {
  const TransactionDetail({
    this.orderId = '',
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId = '',
    this.connectorName = '',
    this.spkluName = '',
    this.pspId = '',
    this.cardNumber = '',
    this.statusCode,
    this.orderedKwh = 0,
    this.usedKwh = 0,
    this.remainingKwh = 0,
    this.paidAmount = 0,
    this.usageAmount = 0,
    this.refundAmount = 0,
    this.pricePerKwh = 0,
    this.serviceAmount = 0,
    this.idleFee = 0,
    this.recordedAt,
  });

  final String orderId;
  final String chargeBoxId;
  final String chargeBoxName;
  final String connectorId;
  final String connectorName;

  /// `namaSpklu`, mis. "SPKLU PLN PUSAT".
  final String spkluName;

  /// Penerbit kartunya, mis. "EM-BNI".
  final String pspId;

  /// Sudah disamarkan backend.
  final String cardNumber;

  final int? statusCode;

  /// `kwhPesan` dan `kwhPakai`.
  final double orderedKwh;
  final double usedKwh;
  final double remainingKwh;

  /// `rpPesan`, `rpPakai`, `rpSisa`.
  final int paidAmount;
  final int usageAmount;
  final int refundAmount;

  final double pricePerKwh;

  /// `rpLayanan`.
  final int serviceAmount;
  final int idleFee;

  final DateTime? recordedAt;

  factory TransactionDetail.fromJson(Map<String, dynamic>? json) {
    // Sebagian angkanya dikirim sebagai teks, sebagian lagi null.
    double number(String key) => switch (json?[key]) {
          final num n => n.toDouble(),
          final String s => double.tryParse(s) ?? 0,
          _ => 0,
        };
    int rupiah(String key) => number(key).round();

    // `connectorId` di endpoint ini berupa angka, bukan teks seperti
    // di endpoint lain.
    final connector = json?['connectorId'];

    return TransactionDetail(
      orderId: json?['orderId'] as String? ?? '',
      chargeBoxId:
          (json?['chargeboxId'] ?? json?['chargeBoxId']) as String? ?? '',
      chargeBoxName:
          (json?['chargeboxName'] ?? json?['chargeBoxName']) as String? ?? '',
      connectorId: connector == null ? '' : '$connector',
      connectorName: json?['connectorName'] as String? ?? '',
      spkluName: json?['namaSpklu'] as String? ?? '',
      pspId: json?['pspId'] as String? ?? '',
      cardNumber: json?['cardNumber'] as String? ?? '',
      statusCode: switch (json?['status']) {
        final num n => n.toInt(),
        final String s => int.tryParse(s),
        _ => null,
      },
      orderedKwh: number('kwhPesan'),
      usedKwh: number('kwhPakai'),
      remainingKwh: number('sisaKwh'),
      paidAmount: rupiah('rpPesan'),
      usageAmount: rupiah('rpPakai'),
      refundAmount: rupiah('rpSisa'),
      pricePerKwh: number('hargaKwh'),
      serviceAmount: rupiah('rpLayanan'),
      idleFee: rupiah('idleFee'),
      recordedAt: switch (json?['tglCatat']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  String toString() => 'TransactionDetail($orderId, $usedKwh/$orderedKwh kWh, '
      'bayar $paidAmount)';
}
