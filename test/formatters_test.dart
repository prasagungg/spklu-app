import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/formatters.dart';

void main() {
  group('formatEnergyWh', () {
    test('satuannya selalu kWh, tidak pernah berganti ke Wh', () {
      // Nilai nyata dari ongoing-kwh pada detik-detik awal pengisian.
      expect(formatEnergyWh(3), '0,003 kWh');
      expect(formatEnergyWh(24), '0,024 kWh');
      expect(formatEnergyWh(127), '0,127 kWh');
      expect(formatEnergyWh(207), '0,207 kWh');
      expect(formatEnergyWh(999), '0,999 kWh');
    });

    test('nilai bulat ditulis tanpa desimal', () {
      expect(formatEnergyWh(1000), '1 kWh');
      expect(formatEnergyWh(6400), '6,4 kWh');
      expect(formatEnergyWh(19500), '19,5 kWh');
    });

    test('nol tetap terbaca sebagai kWh', () {
      expect(formatEnergyWh(0), '0 kWh');
    });

    test('tiap Wh tetap terbedakan', () {
      expect(formatEnergyWh(126), '0,126 kWh');
      expect(formatEnergyWh(127), '0,127 kWh');
    });
  });

  group('formatEnergy dari kWh', () {
    test('angka backend ditampilkan apa adanya, tidak dibulatkan', () {
      // `charged` dari ongoing-kwh dipakai persis seperti yang dikirim:
      // desimalnya tidak dipangkas, karena angka yang berselisih dengan
      // catatan backend lebih buruk daripada angka yang panjang.
      expect(formatEnergy(4.945678), '4,945678 kWh');
      expect(formatEnergy(0.0031), '0,0031 kWh');
      expect(formatEnergy(19.5), '19,5 kWh');
    });

    test('nilai bulat tanpa ",0" di ujungnya', () {
      expect(formatEnergy(0), '0 kWh');
      expect(formatEnergy(5), '5 kWh');
    });

    test('dua bacaan yang berbeda tidak pernah tampil sama', () {
      expect(formatEnergy(0.126), isNot(formatEnergy(0.127)));
      expect(formatEnergy(6.44), isNot(formatEnergy(6.45)));
    });
  });

  group('formatKwh apa adanya', () {
    test('dipakai untuk kWh yang dibeli, selalu satu desimal', () {
      expect(formatKwh(19.5), '19,5 kWh');
      expect(formatKwh(7.8), '7,8 kWh');
      // Sengaja tidak beralih satuan — ini nilai kontrak, bukan meter.
      expect(formatKwh(0.127), '0,1 kWh');
    });
  });

  group('formatRupiah', () {
    test('memakai titik sebagai pemisah ribuan', () {
      expect(formatRupiah(0), 'Rp0');
      expect(formatRupiah(1500), 'Rp1.500');
      expect(formatRupiah(50000), 'Rp50.000');
      expect(formatRupiah(148500), 'Rp148.500');
    });
  });
}
