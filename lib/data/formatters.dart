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

/// 19.5 -> "19,5 kWh" (koma desimal, gaya Indonesia).
///
/// Dipakai untuk nilai yang memang dalam satuan kWh, mis. kWh yang
/// dibeli pada rincian harga.
String formatKwh(double kwh) {
  final text = kwh.toStringAsFixed(1).replaceAll('.', ',');
  return '$text kWh';
}

/// Energi tersalur dari `GET /progress`, yang dilaporkan dalam Wh.
///
/// Satuannya selalu kWh, tetapi jumlah desimalnya menyesuaikan. Mulai
/// 1 kWh dipakai satu desimal seperti desain ("6,4 kWh"); di bawah itu
/// dipakai tiga desimal agar angkanya benar-benar bergerak — dengan
/// satu desimal, 127 Wh tampil "0,1 kWh" dan 3 Wh tampil "0,0 kWh"
/// sehingga terlihat mandek padahal pengisian sedang berjalan.
///
/// 3 -> "0,003 kWh" | 127 -> "0,127 kWh" | 6400 -> "6,4 kWh"
String formatEnergyWh(num watthours) => formatEnergy(watthours / 1000);

/// Bentuk [formatEnergyWh] untuk nilai yang sudah dalam kWh.
String formatEnergy(double kwh) {
  final digits = kwh.abs() >= 1 ? 1 : 3;
  final text = kwh.toStringAsFixed(digits).replaceAll('.', ',');
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
