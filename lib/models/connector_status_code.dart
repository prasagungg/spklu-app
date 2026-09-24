/// Angka `status` satu konektor pada `POST /detail-chargerbox` dan
/// `POST /list-chargerbox`.
///
/// **Bukan kosakata yang sama dengan `BackendStatus`.** Angka di sini
/// menggambarkan keadaan konektornya bagi orang yang berdiri di depan
/// charger — bebas, dipakai, menunggu dibayar — sedangkan
/// `BackendStatus` menggambarkan tahap satu transaksi (`statusProcess`
/// pada `manage-sessioncode` dan `status` pada `ongoing-kwh`). Angka
/// yang sama berarti hal yang berbeda di kedua tempat itu, jadi
/// keduanya sengaja dipisah.
///
/// Keadaan fisik konektornya — kabel sudah tercolok atau belum —
/// bukan urusan angka ini melainkan `POST /check-status-connector`.
class ConnectorStatusCode {
  const ConnectorStatusCode._();

  /// 0 — sudah dipesan, belum sampai pembelian.
  static const int reserved = 0;

  /// 1 — tersedia, bebas dipakai siapa saja.
  static const int available = 1;

  /// 2 — sedang digunakan.
  static const int inUse = 2;

  /// 3 — menunggu pembayaran: ordernya sudah dibuat, belum dibayar.
  static const int awaitingPayment = 3;

  /// 4 — tidak tersedia.
  static const int unavailable = 4;

  /// Apakah [code] menandakan konektor masih bebas dipakai orang baru.
  ///
  /// Null dianggap bebas: data dummy dan sebagian test tidak
  /// menyertakan status, dan menolaknya hanya akan membuat daftar
  /// tampak kosong tanpa sebab.
  static bool isUsable(int? code) => code == null || code == available;
}
