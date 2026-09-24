import 'backend_status.dart';

/// Satu transaksi yang pernah terjadi, dari
/// `GET /transaction/history-transaction`.
///
/// ```json
/// {
///   "pspId": "EM-BNI",
///   "cardNumber": "0123456789012345",
///   "orderId": "8XWS0G9RULEYBLHS48ULF6OFH7",
///   "totalAmount": 12700,
///   "createdDate": "2026-09-23T09:28:44Z"
/// }
/// ```
///
/// `pspId` dan `cardNumber` bisa kosong — transaksi yang tidak pernah
/// sampai dibayar tetap tercatat.
///
/// Endpoint-nya kini dipanggil tanpa body dan mengembalikan seluruh
/// transaksi sekaligus, jadi asal tiap entri — charge box dan
/// konektornya — tidak lagi diketahui dari permintaan yang
/// menghasilkannya. [chargeBoxId] dan kawan-kawannya dibaca dari
/// entrinya sendiri bila ada, dan halaman riwayat memakainya untuk
/// mencari charge box yang bersangkutan di daftar lokasi ini.
class TransactionHistoryEntry {
  const TransactionHistoryEntry({
    required this.orderId,
    this.pspId = '',
    this.cardNumber = '',
    this.totalAmount = 0,
    this.createdAt,
    this.chargeBoxId = '',
    this.chargeBoxName = '',
    this.connectorId,
    this.connectorName = '',
  });

  final String orderId;
  final String pspId;

  /// Nomor kartu apa adanya dari backend. Jangan ditampilkan utuh —
  /// pakai [maskedCard].
  final String cardNumber;

  final int totalAmount;
  final DateTime? createdAt;

  /// Asal transaksinya, bila entrinya menyebutkannya. Kosong pada
  /// versi backend yang masih menitipkan keduanya ke permintaan.
  final String chargeBoxId;
  final String chargeBoxName;
  final int? connectorId;
  final String connectorName;

  factory TransactionHistoryEntry.fromJson(Map<String, dynamic> json) {
    // Ejaan `chargeboxId`/`chargeboxName` dengan b kecil dipakai
    // `detail-history-transaction` dan `ongoing-kwh`; ejaan dengan B
    // besar dipakai sisanya. Keduanya diterima, karena field yang salah
    // eja tidak memunculkan error — hanya diam-diam kosong.
    String text(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return '';
    }

    return TransactionHistoryEntry(
      orderId: json['orderId'] as String? ?? '',
      pspId: json['pspId'] as String? ?? '',
      cardNumber: json['cardNumber'] as String? ?? '',
      totalAmount: (json['totalAmount'] as num?)?.round() ?? 0,
      createdAt: switch (json['createdDate']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
      chargeBoxId: text(const ['chargeboxId', 'chargeBoxId']),
      chargeBoxName: text(const [
        'chargeboxName',
        'chargeBoxName',
        'namaChargebox',
        'namaChargeBox',
      ]),
      // Dikirim sebagai teks di sebagian endpoint dan angka di
      // sebagian lain, jadi diurai lewat satu jalan yang menerima
      // keduanya.
      connectorId: BackendStatus.parse(json['connectorId']),
      connectorName: text(const ['connectorName', 'namaKonektor']),
    );
  }

  /// "6012 **** **** 7890" — backend mengirim nomornya utuh, desain
  /// hanya menampilkan empat digit depan dan belakang.
  ///
  /// Nomor yang terlalu pendek untuk disamarkan ditampilkan apa adanya;
  /// yang kosong menghasilkan tanda hubung.
  String get maskedCard {
    if (cardNumber.isEmpty) return '-';
    if (cardNumber.length < 8) return cardNumber;

    final head = cardNumber.substring(0, 4);
    final tail = cardNumber.substring(cardNumber.length - 4);

    return '$head **** **** $tail';
  }

  /// Pernah dibayar dengan kartu.
  bool get isPaid => cardNumber.isNotEmpty;

  @override
  String toString() =>
      'TransactionHistoryEntry($orderId, $totalAmount, $createdAt)';
}
