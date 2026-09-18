import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/formatters.dart';

void main() {
  group('formatEnergyWh', () {
    test('satuannya selalu kWh, tidak pernah berganti ke Wh', () {
      // Nilai nyata dari /progress pada detik-detik awal pengisian.
      expect(formatEnergyWh(3), '0,003 kWh');
      expect(formatEnergyWh(24), '0,024 kWh');
      expect(formatEnergyWh(127), '0,127 kWh');
      expect(formatEnergyWh(207), '0,207 kWh');
      expect(formatEnergyWh(999), '0,999 kWh');
    });

    test('1 kWh ke atas memakai satu desimal seperti desain', () {
      expect(formatEnergyWh(1000), '1,0 kWh');
      expect(formatEnergyWh(6400), '6,4 kWh');
      expect(formatEnergyWh(19500), '19,5 kWh');
    });

    test('nol tetap terbaca sebagai kWh', () {
      expect(formatEnergyWh(0), '0,000 kWh');
    });

    test('tiga desimal cukup untuk membedakan tiap Wh', () {
      expect(formatEnergyWh(126), '0,126 kWh');
      expect(formatEnergyWh(127), '0,127 kWh');
    });
  });

  group('formatEnergy dari kWh', () {
    test('nilai kecil dapat tiga desimal', () {
      expect(formatEnergy(0.003), '0,003 kWh');
      expect(formatEnergy(0.127), '0,127 kWh');
    });

    test('nilai besar tetap satu desimal', () {
      expect(formatEnergy(6.4), '6,4 kWh');
      expect(formatEnergy(19.5), '19,5 kWh');
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
