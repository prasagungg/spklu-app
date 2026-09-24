/// Format rupiah tanpa paket `intl`: 50000 -> "Rp50.000".
String formatRupiah(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return 'Rp${buffer.toString()}';
}

/// Tarif pecahan: 2466.78 -> "Rp2.466,78".
///
/// Dipakai untuk tarif per kWh, satu-satunya angka rupiah dari backend
/// yang bukan bilangan bulat.
String formatRupiahDecimal(double amount) {
  final whole = formatRupiah(amount.abs().truncate());
  final cents = ((amount.abs() - amount.abs().truncate()) * 100).round();

  return cents == 0
      ? whole
      : '$whole,${cents.toString().padLeft(2, '0')}';
}

/// Angka kWh tanpa satuan, untuk kartu pilihan yang sempit (204:3717).
///
/// Pilihan dari `GET /list-kwh` selalu bulat, dan desainnya menulisnya
/// begitu — "10", bukan "10,0". Nilai pecahan tetap ditampilkan apa
/// adanya kalau suatu saat backend mengirimnya.
String formatKwhNumber(double kwh) => kwh == kwh.roundToDouble()
    ? kwh.round().toString()
    : kwh.toStringAsFixed(1).replaceAll('.', ',');

/// 19.5 -> "19,5 kWh" (koma desimal, gaya Indonesia).
///
/// Dipakai untuk nilai yang memang dalam satuan kWh, mis. kWh yang
/// dibeli pada rincian harga.
String formatKwh(double kwh) {
  final text = kwh.toStringAsFixed(1).replaceAll('.', ',');
  return '$text kWh';
}

/// Bentuk [formatEnergy] untuk nilai yang dilaporkan dalam Wh.
///
/// 3 -> "0,003 kWh" | 127 -> "0,127 kWh" | 6400 -> "6,4 kWh"
String formatEnergyWh(num watthours) => formatEnergy(watthours / 1000);

/// Energi tersalur — `charged` dari
/// `POST /transaction/charging/ongoing-kwh` — **apa adanya**.
///
/// Angkanya tidak dibulatkan dan desimalnya tidak dipangkas: yang
/// tampil di layar adalah bacaan backend persis seperti yang dikirim,
/// hanya dengan koma sebagai pemisah desimal. Pemangkasan sempat
/// membuat dua bacaan yang berbeda tampil sama — 0,127 dan 0,126
/// keduanya menjadi "0,1 kWh" — dan angka yang berselisih dengan
/// catatan backend lebih buruk daripada angka yang panjang.
///
/// Nilai bulat ditulis tanpa desimal, karena ".0" bukan bagian dari
/// angkanya: 0 -> "0 kWh" | 5 -> "5 kWh".
///
/// 0.003 -> "0,003 kWh" | 6.4 -> "6,4 kWh" | 4.945678 -> "4,945678 kWh"
String formatEnergy(double kwh) {
  final text = kwh == kwh.roundToDouble()
      ? kwh.toStringAsFixed(0)
      : kwh.toString().replaceAll('.', ',');
  return '$text kWh';
}

/// Nama bulan ringkas gaya Indonesia.
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// "21 Sep 2026, 16:42".
///
/// Waktu dari backend berformat UTC; yang ditampilkan adalah waktu
/// setempat, karena itulah jam yang dilihat pengguna di lokasi.
String formatDateTime(DateTime? time) {
  if (time == null) return '-';

  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');

  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}, '
      '${two(local.hour)}:${two(local.minute)}';
}
