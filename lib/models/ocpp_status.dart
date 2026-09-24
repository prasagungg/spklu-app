/// Status OCPP 1.6 satu konektor, dari `POST /check-status-connector`.
///
/// Inilah satu-satunya sumber yang benar-benar tahu apakah kabelnya
/// sudah tercolok ke kendaraan: angka `status` pada daftar charge box
/// menggambarkan tahap transaksinya, bukan keadaan fisik konektornya.
///
/// Seluruh aplikasi menafsirkan kosakata ini lewat berkas ini saja,
/// supaya perubahan dari backend cukup diikuti di satu tempat.
class OcppStatus {
  const OcppStatus._();

  /// Bebas, kabel belum terpasang.
  static const String available = 'Available';

  /// Kabel sudah terpasang dan charger siap dimulai.
  static const String preparing = 'Preparing';

  static const String charging = 'Charging';

  /// Pengisian tertahan dari sisi charger.
  static const String suspendedEvse = 'SuspendedEVSE';

  /// Pengisian tertahan dari sisi kendaraan, mis. baterai penuh.
  static const String suspendedEv = 'SuspendedEV';

  /// Sesi selesai, kabel biasanya masih terpasang.
  static const String finishing = 'Finishing';

  /// Dipesan untuk orang lain.
  static const String reserved = 'Reserved';

  /// Sengaja dimatikan operator.
  static const String unavailable = 'Unavailable';

  /// Charger melaporkan gangguan.
  static const String faulted = 'Faulted';

  /// Apakah [status] berarti kabelnya sudah terpasang ke kendaraan.
  ///
  /// "Preparing" adalah tanda yang ditunggu halaman Hubungkan Konektor.
  /// Keadaan sesudahnya ikut dianggap terpasang supaya halaman itu
  /// tidak menggantung bila charger sempat melewati "Preparing" —
  /// misalnya karena sesinya sudah jalan lebih dulu.
  ///
  /// Status yang **tidak dikenal tidak dianggap terpasang**. Menebaknya
  /// akan mengirim perintah start yang pasti ditolak charger.
  static bool isPluggedIn(String status) => switch (status) {
        preparing ||
        charging ||
        suspendedEv ||
        suspendedEvse ||
        finishing =>
          true,
        _ => false,
      };

  /// Charger sedang tidak bisa dipakai, dan menunggu lebih lama tidak
  /// akan mengubah apa pun — petugas yang harus turun tangan.
  static bool isBroken(String status) =>
      status == faulted || status == unavailable;
}
