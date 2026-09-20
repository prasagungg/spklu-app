import 'charge_box.dart';
import 'connector.dart';
import 'kwh_price.dart';
import 'order.dart';

/// Satu sesi pengisian yang dibawa dari halaman konfirmasi sampai
/// halaman "Pengisian Dimulai".
///
/// Nomor referensi, kode sesi, dan rincian harganya datang dari order
/// yang dibuat `POST /transaction/push-order`.
class ChargingSession {
  const ChargingSession({
    required this.chargeBox,
    required this.connector,
    required this.sessionCode,
    required this.reference,
    required this.createdAt,
    this.price,
    this.orderId = '',
  });

  final ChargeBox chargeBox;
  final Connector connector;

  /// Rincian harga yang dibeli pengguna.
  ///
  /// Null untuk sesi yang dilanjutkan dari daftar charge box: aplikasi
  /// tidak tahu berapa yang dibayarkan pengguna sebelumnya, jadi baris
  /// pembayaran disembunyikan alih-alih menampilkan angka karangan.
  final PriceBreakdown? price;

  /// Kode yang diperlukan pengguna untuk mengakhiri sesi, mis. "29".
  final String sessionCode;

  /// Nomor referensi transaksi dari backend (`partnerReference`).
  final String reference;

  /// Identitas order, mis. "ADWTJU5D56QGZNXTTNOX9YZFTN". Kosong pada
  /// sesi yang dilanjutkan dari daftar.
  final String orderId;

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

  /// Sesi baru dari order yang sudah dibuat backend.
  factory ChargingSession.fromOrder({
    required ChargeBox chargeBox,
    required Connector connector,
    required Order order,
    required DateTime now,
  }) {
    return ChargingSession(
      chargeBox: chargeBox,
      connector: connector,
      price: order,
      orderId: order.orderId,
      sessionCode: order.sessionCode,
      reference: order.partnerReference,
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
