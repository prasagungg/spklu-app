/// Angka `status` yang dikirim backend pada konektor.
///
/// Kelima nilainya menggambarkan perjalanan satu sesi pengisian, dari
/// konektor yang baru dipesan sampai sesi yang sudah selesai. Nilai di
/// luar daftar ini dianggap tidak bisa dipakai.
///
/// Seluruh aplikasi menafsirkannya lewat berkas ini saja, supaya
/// perubahan kosakata backend cukup diikuti di satu tempat.
class BackendStatus {
  const BackendStatus._();

  /// 0 — sedang dipesan orang lain.
  static const int reserved = 0;

  /// 1 — belum dibayar atau masih bisa dipakai.
  static const int available = 1;

  /// 2 — sudah dibayar, pengguna diminta menghubungkan konektor.
  static const int awaitingConnector = 2;

  /// 3 — sedang mengisi.
  static const int charging = 3;

  /// 4 — pengisian sudah selesai.
  static const int finished = 4;

  /// Apakah [code] menandakan konektor masih bebas dipakai orang baru.
  ///
  /// Null dianggap bebas: data dummy dan sebagian test tidak
  /// menyertakan status, dan menolaknya hanya akan membuat daftar
  /// tampak kosong tanpa sebab.
  static bool isUsable(int? code) => code == null || code == available;

  static int? parse(dynamic value) => switch (value) {
        final num n => n.toInt(),
        final String s => int.tryParse(s),
        _ => null,
      };
}
