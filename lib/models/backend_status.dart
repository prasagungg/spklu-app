import 'connector_status_code.dart';

/// Tahap satu transaksi: `statusProcess` pada `manage-sessioncode` dan
/// `status` pada `ongoing-kwh`.
///
/// **Bukan kosakata yang sama dengan [ConnectorStatusCode]**, yang
/// dipakai angka `status` milik konektor di daftar dan detail charge
/// box. Angka yang sama berarti hal yang berbeda di kedua tempat itu.
///
/// Seluruh aplikasi menafsirkannya lewat berkas ini saja, supaya
/// perubahan kosakata backend cukup diikuti di satu tempat.
class BackendStatus {
  const BackendStatus._();

  /// 0 — konektornya baru dipesan; ordernya belum dibuat.
  static const int booked = 0;

  /// 1 — belum dibayar atau masih bisa dipakai.
  static const int available = 1;

  /// 2 — sudah dibayar, pengguna diminta menghubungkan konektor.
  static const int awaitingConnector = 2;

  /// 3 — sedang mengisi.
  static const int charging = 3;

  /// 4 — pengisian sudah selesai.
  static const int finished = 4;

  static int? parse(dynamic value) => switch (value) {
        final num n => n.toInt(),
        final String s => int.tryParse(s),
        _ => null,
      };
}
