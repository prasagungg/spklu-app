/// Rincian harga untuk sejumlah kWh, dari `POST /count-kwh`.
///
/// ```json
/// {
///   "chargeBoxId": "CB-SMR-01", "connectorId": "1", "kwh": 10,
///   "rpJaminanSpklu": 0, "rpAdmin": 0, "rpDiskon": 0,
///   "rpPerKwh": 2466.78, "rpPpj": 2467, "rpPpn": 0,
///   "rpTotal": 27135, "rpLayanan": 0, "rpMaterai": 0, "idleFee": 0
/// }
/// ```
///
/// Seluruh angkanya dipakai apa adanya. Aplikasi tidak menghitung
/// sendiri, bahkan tidak mengalikan [kwh] dengan [rpPerKwh]: backend
/// yang berwenang atas harga, dan angka turunan yang tidak cocok dengan
/// [rpTotal] hanya akan membingungkan pengguna.
class KwhPrice {
  const KwhPrice({
    required this.kwh,
    required this.rpTotal,
    this.chargeBoxId = '',
    this.connectorId = '',
    this.rpPerKwh = 0,
    this.rpPpj = 0,
    this.rpPpn = 0,
    this.rpAdmin = 0,
    this.rpLayanan = 0,
    this.rpMaterai = 0,
    this.rpDiskon = 0,
    this.rpJaminanSpklu = 0,
    this.idleFee = 0,
  });

  final String chargeBoxId;
  final String connectorId;

  /// kWh yang dibeli. Dikirim balik backend apa adanya.
  final double kwh;

  /// Tarif per kWh. Pecahan, mis. 2466,78.
  final double rpPerKwh;

  /// Pajak penerangan jalan.
  final int rpPpj;

  final int rpPpn;
  final int rpAdmin;
  final int rpLayanan;
  final int rpMaterai;
  final int rpDiskon;

  /// Jaminan yang ditahan SPKLU.
  final int rpJaminanSpklu;

  /// Denda bila kendaraan dibiarkan terhubung setelah selesai.
  final int idleFee;

  /// Yang dibayar pengguna.
  final int rpTotal;

  factory KwhPrice.fromJson(Map<String, dynamic>? json) {
    double number(String key) => (json?[key] as num?)?.toDouble() ?? 0;
    int rupiah(String key) => (json?[key] as num?)?.round() ?? 0;

    return KwhPrice(
      chargeBoxId: json?['chargeBoxId'] as String? ?? '',
      connectorId: json?['connectorId'] as String? ?? '',
      kwh: number('kwh'),
      rpPerKwh: number('rpPerKwh'),
      rpPpj: rupiah('rpPpj'),
      rpPpn: rupiah('rpPpn'),
      rpAdmin: rupiah('rpAdmin'),
      rpLayanan: rupiah('rpLayanan'),
      rpMaterai: rupiah('rpMaterai'),
      rpDiskon: rupiah('rpDiskon'),
      rpJaminanSpklu: rupiah('rpJaminanSpklu'),
      idleFee: rupiah('idleFee'),
      rpTotal: rupiah('rpTotal'),
    );
  }

  /// Baris biaya tambahan yang layak ditampilkan.
  ///
  /// Sebagian besar bernilai nol pada kebanyakan transaksi; menampilkan
  /// deretan "Rp0" hanya menenggelamkan angka yang penting. Yang nol
  /// karena itu disembunyikan.
  List<({String label, int amount})> get extraCharges => [
        for (final row in [
          (label: 'Biaya Admin', amount: rpAdmin),
          (label: 'Biaya Layanan', amount: rpLayanan),
          (label: 'Bea Materai', amount: rpMaterai),
          (label: 'Jaminan SPKLU', amount: rpJaminanSpklu),
          (label: 'Denda Idle', amount: idleFee),
          (label: 'Diskon', amount: -rpDiskon),
        ])
          if (row.amount != 0) row,
      ];

  @override
  String toString() => 'KwhPrice($kwh kWh, total $rpTotal)';
}
