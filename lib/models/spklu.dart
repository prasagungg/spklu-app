import 'backend_status.dart';
import 'charge_box.dart';

/// Satu lokasi SPKLU beserta charge box di dalamnya, dari
/// `POST /list-chargerbox`.
///
/// Keterangan lokasi — nama, alamat, daya — belum ditampilkan di layar
/// mana pun, tetapi diurai supaya tersedia ketika dibutuhkan dan supaya
/// bentuk response terdokumentasi di satu tempat.
class Spklu {
  const Spklu({
    required this.id,
    required this.chargeBoxes,
    this.nama = '',
    this.alamat = '',
    this.daya = '',
    this.edgeControllerId = '',
    this.statusCode,
  });

  /// SPKLU kosong — dipakai saat backend membalas tanpa `data`.
  const Spklu.empty()
    : id = '',
      nama = '',
      alamat = '',
      daya = '',
      edgeControllerId = '',
      statusCode = null,
      chargeBoxes = const [];

  /// `idSpklu`, mis. "SPKLU-SMR".
  final String id;

  /// `namaSpklu`, mis. "PLN Charging Station Sisingamangaraja".
  final String nama;

  /// `alamatSpklu`.
  final String alamat;

  /// `dayaSpklu`, mis. "200 kW". Kosong sejak daya pindah ke tiap
  /// charge box.
  final String daya;

  /// `idEdgeController`, mis. "EC-00001-2" — unit yang melayani SPKLU
  /// ini. Dipakai halaman Charge Box CSMS sebagai isian yang sudah
  /// terkunci, supaya petugas tidak mengetik ulang nilai yang sudah
  /// diketahui backend.
  final String edgeControllerId;

  /// Angka `status` apa adanya dari backend.
  final int? statusCode;

  final List<ChargeBox> chargeBoxes;

  factory Spklu.fromJson(Map<String, dynamic> json) {
    // `chargeBoxs` ejaan sekarang; `chargeBoxes` versi sebelumnya.
    final raw = json['chargeBoxs'] ?? json['chargeBoxes'];
    final items = raw is List
        ? raw.whereType<Map<String, dynamic>>().toList()
        : const [];

    return Spklu(
      id: json['idSpklu'] as String? ?? '',
      nama: json['namaSpklu'] as String? ?? '',
      alamat: json['alamatSpklu'] as String? ?? '',
      daya: json['dayaSpklu'] as String? ?? '',
      edgeControllerId: json['idEdgeController'] as String? ?? '',
      statusCode: BackendStatus.parse(json['status']),
      chargeBoxes: [
        for (var i = 0; i < items.length; i++)
          ChargeBox.fromJson(items[i], number: i + 1),
      ],
    );
  }
}
