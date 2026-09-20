import '../models/booking.dart';

/// Booking konektor yang sedang dipegang unit ini.
///
/// Satu unit melayani satu pengguna dalam satu waktu, jadi cukup satu
/// booking yang diingat. Dipegang oleh `ChargingScope` — bukan variabel
/// global — supaya setiap aplikasi (termasuk tiap test) punya miliknya
/// sendiri.
///
/// Gunanya: konektor yang sudah dikunci lewat R0 harus dilepas lagi
/// kalau pengguna meninggalkan alur pembelian sebelum pengisian dimulai.
/// Tanpa catatan ini, konektor yang ditinggalkan akan terkunci selamanya
/// dan tidak bisa dipakai siapa pun.
class ActiveBooking {
  String? _chargeBoxId;
  int? _connectorId;
  BookingStage _stage = BookingStage.selected;

  /// Ada booking yang masih bisa dibatalkan.
  bool get isHeld => _chargeBoxId != null;

  String? get chargeBoxId => _chargeBoxId;
  int? get connectorId => _connectorId;

  /// Tahap terakhir yang dilaporkan.
  BookingStage get stage => _stage;

  /// Mencatat booking yang baru saja berhasil dikunci (R0).
  void hold({required String chargeBoxId, required int connectorId}) {
    _chargeBoxId = chargeBoxId;
    _connectorId = connectorId;
    _stage = BookingStage.selected;
  }

  /// Menaikkan tahap yang diingat, mengikuti laporan kemajuan.
  void advance(BookingStage stage) {
    if (isHeld) _stage = stage;
  }

  /// Melupakan booking **tanpa** membatalkannya.
  ///
  /// Dipanggil begitu pengisian benar-benar dimulai: sejak saat itu
  /// konektornya sedang dipakai, bukan sekadar dipesan, jadi kembalinya
  /// pengguna ke daftar tidak boleh melepasnya.
  void forget() {
    _chargeBoxId = null;
    _connectorId = null;
    _stage = BookingStage.selected;
  }
}
