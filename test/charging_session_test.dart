import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/models/kwh_price.dart';

ChargingSession _session() {
  final box = DemoData.chargeBoxes[3];
  return ChargingSession.demo(
    chargeBox: box,
    connector: box.connectors.first,
    // Rp50.000 untuk 19,5 kWh — angka bulat supaya pembulatan
    // tagihan ke bawah mudah dibaca.
    price: const KwhPrice(kwh: 19.5, rpTotal: 50000),
    now: DateTime(2026, 9, 16, 18, 40, 39),
  );
}

void main() {
  test('biaya pemakaian dihitung proporsional dan dibulatkan ke bawah', () {
    final session = _session();

    // 6,4 dari 19,5 kWh -> 16.410 -> dibulatkan ke bawah jadi 16.000,
    // sesuai angka pada desain Figma.
    expect(session.usageCostFor(6.4), 16000);
    expect(session.refundFor(6.4), 34000);
  });

  test('belum ada energi tersalur berarti dana kembali penuh', () {
    final session = _session();

    expect(session.usageCostFor(0), 0);
    expect(session.refundFor(0), 50000);
  });

  test('pemakaian tidak pernah melebihi nominal yang dibayar', () {
    final session = _session();

    expect(session.usageCostFor(999), 50000);
    expect(session.refundFor(999), 0);
  });

  test('breadcrumb menggabungkan badge, nama box, dan konektor', () {
    expect(_session().breadcrumb, '04 • CS DC Charger • Gun 1');
  });

  test('tanggal transaksi diformat untuk ditampilkan', () {
    expect(_session().formattedDate, '2026-09-16 18:40:39');
  });
}
