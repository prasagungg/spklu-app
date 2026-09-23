/// Satu transaksi yang pernah terjadi pada sebuah konektor, dari
/// `POST /transaction/history-transaction`.
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
class TransactionHistoryEntry {
  const TransactionHistoryEntry({
    required this.orderId,
    this.pspId = '',
    this.cardNumber = '',
    this.totalAmount = 0,
    this.createdAt,
  });

  final String orderId;
  final String pspId;

  /// Nomor kartu apa adanya dari backend. Jangan ditampilkan utuh —
  /// pakai [maskedCard].
  final String cardNumber;

  final int totalAmount;
  final DateTime? createdAt;

  factory TransactionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TransactionHistoryEntry(
      orderId: json['orderId'] as String? ?? '',
      pspId: json['pspId'] as String? ?? '',
      cardNumber: json['cardNumber'] as String? ?? '',
      totalAmount: (json['totalAmount'] as num?)?.round() ?? 0,
      createdAt: switch (json['createdDate']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
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
