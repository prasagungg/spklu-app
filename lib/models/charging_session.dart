import 'charge_box.dart';
import 'connector.dart';
import 'kwh_price.dart';

/// Satu sesi pengisian yang dibawa dari halaman konfirmasi sampai
/// halaman "Pengisian Dimulai".
///
/// Nomor referensi dan kode sesi masih dibangkitkan lokal untuk demo —
/// nanti keduanya datang dari backend saat transaksi dibuat.
class ChargingSession {
  const ChargingSession({
    required this.chargeBox,
    required this.connector,
    required this.sessionCode,
    required this.reference,
    required this.createdAt,
    this.price,
  });

  final ChargeBox chargeBox;
  final Connector connector;

  /// Rincian harga yang dibeli pengguna.
  ///
  /// Null untuk sesi yang dilanjutkan dari daftar charge box: aplikasi
  /// tidak tahu berapa yang dibayarkan pengguna sebelumnya, jadi baris
  /// pembayaran disembunyikan alih-alih menampilkan angka karangan.
  final KwhPrice? price;

  /// Kode yang diperlukan pengguna untuk mengakhiri sesi, mis. "29".
  final String sessionCode;

  /// Nomor referensi transaksi, mis. "93CHROVO27092418401".
  final String reference;

  final DateTime createdAt;

  /// Sesi yang dilanjutkan: pengguna menekan charge box yang sudah
  /// berstatus "Preparing" atau "Charging", bukan memulai dari awal.
  factory ChargingSession.resumed({
    required ChargeBox chargeBox,
    required Connector connector,
    required DateTime now,
    int? transactionId,
  }) {
    return ChargingSession(
      chargeBox: chargeBox,
      connector: connector,
      sessionCode: transactionId?.toString() ?? '-',
      reference: '-',
      createdAt: now,
    );
  }

  /// Data demo mengikuti angka pada desain Figma.
  factory ChargingSession.demo({
    required ChargeBox chargeBox,
    required Connector connector,
    required KwhPrice price,
    required DateTime now,
  }) {
    return ChargingSession(
      chargeBox: chargeBox,
      connector: connector,
      price: price,
      sessionCode: '29',
      reference: '93CHROVO27092418401',
      createdAt: now,
    );
  }

  /// "04 • CS DC Charger • CCS2 - 200 kW DC"
  String get breadcrumb =>
      '${chargeBox.badge} • ${chargeBox.name} • ${connector.name}';

  String get jenisLayanan => 'EV Charging';

  /// Apakah sesi ini punya data pembelian.
  bool get hasPurchase => price != null;

  /// Biaya pemakaian untuk [energyKwh] yang sudah tersalur, dihitung
  /// proporsional terhadap kWh yang dibeli lalu dibulatkan ke bawah per
  /// seribu rupiah. Dibulatkan ke bawah agar tagihan tidak pernah
  /// melebihi pemakaian sebenarnya.
  ///
  /// Null bila sesi dilanjutkan tanpa data pembelian.
  int? usageCostFor(double energyKwh) {
    final purchase = price;
    if (purchase == null || purchase.kwh <= 0) return null;
    final ratio = (energyKwh / purchase.kwh).clamp(0.0, 1.0);
    final raw = ratio * purchase.rpTotal;
    return (raw ~/ 1000) * 1000;
  }

  /// Sisa yang dikembalikan setelah pengisian dihentikan.
  int? refundFor(double energyKwh) {
    final purchase = price;
    final usage = usageCostFor(energyKwh);
    if (purchase == null || usage == null) return null;
    return purchase.rpTotal - usage;
  }

  /// "2026-09-16 18:40:39"
  String get formattedDate {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${createdAt.year}-${two(createdAt.month)}-${two(createdAt.day)} '
        '${two(createdAt.hour)}:${two(createdAt.minute)}:${two(createdAt.second)}';
  }
}
