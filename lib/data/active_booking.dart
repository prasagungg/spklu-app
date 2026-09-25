/// Booking konektor yang sedang dipegang unit ini.
///
/// Satu unit melayani satu pengguna dalam satu waktu, jadi cukup satu
/// booking yang diingat. Dipegang oleh `ChargingScope` — bukan variabel
/// global — supaya setiap aplikasi (termasuk tiap test) punya miliknya
/// sendiri.
///
/// Dua gunanya:
///
/// 1. Konektor yang sudah dikunci lewat R0 harus dilepas lagi kalau
///    pengguna meninggalkan alur pembelian sebelum pengisian dimulai.
///    Tanpa catatan ini, konektor yang ditinggalkan akan terkunci
///    selamanya dan tidak bisa dipakai siapa pun.
/// 2. Setelah pengisian jalan, [orderId] tetap diingat. Semua endpoint
///    pengisian berkunci order, sedangkan daftar charge box tidak
///    membawanya — tanpa ingatan ini pengguna yang pulang ke daftar
///    tidak akan bisa kembali memantau atau menghentikan sesinya
///    sendiri.
class ActiveBooking {
  String? _chargeBoxId;
  int? _connectorId;
  String? _reservationId;
  String? _orderId;
  String? _sessionCode;
  bool _charging = false;

  /// Ada booking atau sesi yang sedang diingat.
  bool get isHeld => _chargeBoxId != null;

  /// Pengisiannya sudah dimulai, jadi bookingnya tidak boleh dibatalkan
  /// lagi saat pengguna kembali ke daftar.
  bool get isCharging => _charging;

  /// Order yang sedang mengisi, bila ada.
  String? get orderId => _orderId;

  /// Kode sesi yang ditunjukkan ke pengguna saat pengisian dimulai.
  String? get sessionCode => _sessionCode;

  String? get chargeBoxId => _chargeBoxId;
  int? get connectorId => _connectorId;

  /// Pemesanan yang sedang dipegang. Wajib dibawa `push-order` dan
  /// `cancelled-connector`.
  String? get reservationId => _reservationId;

  /// Mencatat pemesanan yang baru saja berhasil dibuat.
  void hold({
    required String chargeBoxId,
    required int connectorId,
    required String reservationId,
    required String sessionCode,
  }) {
    _chargeBoxId = chargeBoxId;
    _connectorId = connectorId;
    _reservationId = reservationId;
    _sessionCode = sessionCode;
    _orderId = null;
    _charging = false;
  }

  /// Menandai pengisiannya sudah dimulai.
  ///
  /// Sejak saat itu konektornya sedang dipakai, bukan sekadar dipesan,
  /// jadi kembalinya pengguna ke daftar tidak boleh melepasnya —
  /// tetapi [orderId] tetap diingat supaya sesinya bisa dibuka lagi.
  void startedCharging({required String orderId}) {
    _orderId = orderId;
    _charging = true;
  }

  /// Apakah sesi yang sedang mengisi ada di konektor ini.
  bool isChargingOn({required String chargeBoxId, required int connectorId}) =>
      _charging && chargeBoxId == _chargeBoxId && connectorId == _connectorId;

  /// Order yang sedang mengisi pada konektor ini, bila cocok.
  ///
  /// Dipakai halaman daftar untuk menyambungkan kembali pengguna ke
  /// sesinya sendiri.
  String? orderOn({required String chargeBoxId, required int connectorId}) =>
      isChargingOn(chargeBoxId: chargeBoxId, connectorId: connectorId)
      ? _orderId
      : null;

  /// Kode sesi yang berlaku untuk konektor ini, bila sesinya dimulai
  /// dari unit ini juga.
  String? sessionCodeOn({
    required String chargeBoxId,
    required int connectorId,
  }) => isChargingOn(chargeBoxId: chargeBoxId, connectorId: connectorId)
      ? _sessionCode
      : null;

  /// Melupakan seluruhnya — booking maupun sesi yang sudah jalan.
  void forget() {
    _chargeBoxId = null;
    _connectorId = null;
    _reservationId = null;
    _orderId = null;
    _sessionCode = null;
    _charging = false;
  }
}
