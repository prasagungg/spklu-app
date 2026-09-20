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
    this.statusCode,
  });

  /// SPKLU kosong — dipakai saat backend membalas tanpa `data`.
  const Spklu.empty()
      : id = '',
        nama = '',
        alamat = '',
        daya = '',
        statusCode = null,
        chargeBoxes = const [];

  /// `idSpklu`, mis. "SPKLU-SMR".
  final String id;

  /// `namaSpklu`, mis. "PLN Charging Station Sisingamangaraja".
  final String nama;

  /// `alamatSpklu`.
  final String alamat;

  /// `dayaSpklu`, mis. "200 kW". Teks apa adanya, bukan angka.
  final String daya;

  /// Angka `status` apa adanya dari backend.
  final int? statusCode;

  final List<ChargeBox> chargeBoxes;

  factory Spklu.fromJson(Map<String, dynamic> json) {
    final raw = json['chargeBoxes'];
    final items =
        raw is List ? raw.whereType<Map<String, dynamic>>().toList() : const [];

    return Spklu(
      id: json['idSpklu'] as String? ?? '',
      nama: json['namaSpklu'] as String? ?? '',
      alamat: json['alamatSpklu'] as String? ?? '',
      daya: json['dayaSpklu'] as String? ?? '',
      statusCode: BackendStatus.parse(json['status']),
      chargeBoxes: [
        for (var i = 0; i < items.length; i++)
          ChargeBox.fromJson(items[i], number: i + 1),
      ],
    );
  }
}
