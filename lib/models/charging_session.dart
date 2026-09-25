import 'billing.dart';
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
    this.billing,
    this.expiresAt,
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

  /// Tagihan yang benar-benar dibayar. Terisi setelah kartu ditempelkan
  /// dan pembayarannya berhasil.
  final BillingInquiry? billing;

  /// Batas waktu order ini, dari `sessionExpiredTime` pada
  /// `POST /transaction/push-order`.
  ///
  /// Inilah sumber hitung mundur "Selesaikan dalam" — bukan durasi
  /// tetap di aplikasi, karena backend yang menentukan kapan ordernya
  /// kedaluwarsa (setelah itu ia membalas kode `22`).
  ///
  /// Null pada sesi yang dilanjutkan dari daftar charge box: ordernya
  /// tidak dibuat di unit ini, jadi batas waktunya tidak diketahui.
  final DateTime? expiresAt;

  /// Sisa waktu order terhadap [now], tidak pernah negatif.
  ///
  /// Dihitung ulang dari jam dinding setiap kali dipanggil supaya
  /// hitung mundur tetap benar walau layar sempat ditinggalkan.
  Duration? remainingAt(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return null;

    final left = expiry.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Salinan dengan bukti pembayarannya.
  ChargingSession paidWith(BillingInquiry billing) => ChargingSession(
    chargeBox: chargeBox,
    connector: connector,
    sessionCode: sessionCode,
    reference: reference,
    createdAt: createdAt,
    price: price,
    orderId: orderId,
    billing: billing,
    // Pembayaran memperbarui tenggat sesinya; batas waktu order
    // hanya dipakai selama belum ada yang dibayar.
    expiresAt: billing.sessionExpiredAt ?? expiresAt,
  );

  /// Yang benar-benar dibayar pengguna.
  ///
  /// Tagihan bisa berbeda dari total order — inquiry menambahkan `fee`,
  /// `idleFee`, dan `serviceFee` — jadi yang dipakai untuk rincian akhir
  /// adalah angka yang didebit, bukan angka order.
  ///
  /// Tidak dibulatkan: angka yang ditampilkan harus sama persis dengan
  /// yang didebit backend, termasuk desimalnya.
  num? get paidAmount => billing?.totalAmount ?? price?.rpTotal;

  final DateTime createdAt;

  /// Sesi yang dilanjutkan: pengguna menekan charge box yang sudah
  /// berstatus "Preparing" atau "Charging", bukan memulai dari awal.
  factory ChargingSession.resumed({
    required ChargeBox chargeBox,
    required Connector connector,
    required DateTime now,
    String orderId = '',
  }) {
    return ChargingSession(
      chargeBox: chargeBox,
      connector: connector,
      sessionCode: '-',
      reference: '-',
      createdAt: now,
      orderId: orderId,
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
      expiresAt: order.sessionExpiredAt,
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
  num? usageCostFor(double energyKwh) {
    final purchase = price;
    final paid = paidAmount;
    if (purchase == null || paid == null || purchase.kwh <= 0) return null;
    final ratio = (energyKwh / purchase.kwh).clamp(0.0, 1.0);
    final raw = ratio * paid;
    return (raw ~/ 1000) * 1000;
  }

  /// Sisa yang dikembalikan setelah pengisian dihentikan.
  num? refundFor(double energyKwh) {
    final paid = paidAmount;
    final usage = usageCostFor(energyKwh);
    if (paid == null || usage == null) return null;
    return paid - usage;
  }

  /// "2026-09-16 18:40:39"
  String get formattedDate {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${createdAt.year}-${two(createdAt.month)}-${two(createdAt.day)} '
        '${two(createdAt.hour)}:${two(createdAt.minute)}:${two(createdAt.second)}';
  }
}
