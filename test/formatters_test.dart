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

  group('formatKwhNumber', () {
    /// Angka kWh ditampilkan persis seperti yang dikirim backend: 10
    /// tetap "10", bukan "10,0", dan 1.6 tetap "1,6".
    test('apa adanya, tanpa desimal karangan', () {
      expect(formatKwhNumber(10), '10');
      expect(formatKwhNumber(1.6), '1,6');
      expect(formatKwhNumber(0.127), '0,127');
      expect(formatEnergy(10), '10 kWh');
      expect(formatEnergy(1.6), '1,6 kWh');
    });
  });

  group('formatRupiah', () {
    test('memakai titik sebagai pemisah ribuan', () {
      expect(formatRupiah(0), 'Rp0');
      expect(formatRupiah(1500), 'Rp1.500');
      expect(formatRupiah(50000), 'Rp50.000');
      expect(formatRupiah(148500), 'Rp148.500');
    });

    test('desimal dari backend ditampilkan apa adanya', () {
      // Tagihan sungguhan kerap pecahan; membulatkannya membuat angka
      // di layar berselisih dengan yang didebit.
      expect(formatRupiah(25161.156), 'Rp25.161,156');
      expect(formatRupiah(2466.78), 'Rp2.466,78');
      expect(formatRupiah(1500.5), 'Rp1.500,5');
    });

    test('nilai bulat tidak ditulis dengan ",0"', () {
      expect(formatRupiah(50000.0), 'Rp50.000');
      expect(formatRupiah(0.0), 'Rp0');
    });

    test('nilai negatif memakai tanda di depan', () {
      // Baris "Diskon" dikirim sebagai angka negatif.
      expect(formatRupiah(-5000), '-Rp5.000');
    });
  });
}
