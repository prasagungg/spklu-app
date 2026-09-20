/// Penerbit uang elektronik yang dikenal backend, dikenali dari empat
/// digit pertama nomor kartu.
///
/// Prefix yang tidak ada di sini dibalas `responseCode` `05`,
/// "E-Money Provider Is Not Supported".
const Map<String, String> emoneyIssuers = {
  '0123': 'EM-BNI',
  '4567': 'EM-BRI',
  '8901': 'EM-BCA',
  '2345': 'EM-MANDIRI',
};

/// Penerbit untuk [cardNumber], atau null bila prefiksnya tidak dikenal.
String? issuerOf(String cardNumber) => cardNumber.length < 4
    ? null
    : emoneyIssuers[cardNumber.substring(0, 4)];

/// Tagihan untuk satu order pada satu kartu.
///
/// Bentuk yang sama dipakai `POST /transaction/inquiry-billing` dan
/// `POST /transaction/payment-billing`; yang kedua menambahkan
/// [bankLog].
///
/// ```json
/// {
///   "orderId": "QHGQM7SNQ6IY7GQLQDSLTY2RJI",
///   "pspId": "EM-BNI", "cardNumber": "0123456789012345",
///   "amount": 25400, "fee": 0, "idleFee": 0, "serviceFee": 0,
///   "totalAmount": 25400, "sessionCode": ""
/// }
/// ```
class BillingInquiry {
  const BillingInquiry({
    required this.orderId,
    required this.totalAmount,
    this.pspId = '',
    this.cardNumber = '',
    this.amount = 0,
    this.fee = 0,
    this.idleFee = 0,
    this.serviceFee = 0,
    this.bankLog = '',
  });

  final String orderId;

  /// Penerbit kartu yang dikenali backend, mis. "EM-BNI".
  final String pspId;

  final String cardNumber;

  /// Pokok tagihan, sebelum biaya tambahan.
  final int amount;

  final int fee;
  final int idleFee;
  final int serviceFee;

  /// Yang didebit dari kartu. Inilah nilai yang harus dikirim sebagai
  /// `amount` saat membayar — bukan total order.
  final int totalAmount;

  /// Bukti transaksi dari mesin kartu. Hanya terisi pada jawaban
  /// pembayaran.
  final String bankLog;

  factory BillingInquiry.fromJson(Map<String, dynamic>? json) {
    int rupiah(String key) => (json?[key] as num?)?.round() ?? 0;

    return BillingInquiry(
      orderId: json?['orderId'] as String? ?? '',
      pspId: json?['pspId'] as String? ?? '',
      cardNumber: json?['cardNumber'] as String? ?? '',
      amount: rupiah('amount'),
      fee: rupiah('fee'),
      idleFee: rupiah('idleFee'),
      serviceFee: rupiah('serviceFee'),
      totalAmount: rupiah('totalAmount'),
      bankLog: json?['bankLog'] as String? ?? '',
    );
  }

  /// Empat digit terakhir, untuk ditampilkan tanpa membuka nomornya.
  String get maskedCard => cardNumber.length < 4
      ? cardNumber
      : '•••• ${cardNumber.substring(cardNumber.length - 4)}';

  /// Sudah dibayar — jawaban pembayaran membawa bukti transaksinya.
  bool get isPaid => bankLog.isNotEmpty;

  @override
  String toString() =>
      'BillingInquiry($orderId, $pspId, total $totalAmount'
      '${isPaid ? ', dibayar' : ''})';
}
