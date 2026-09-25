import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/connector.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/theme/app_theme.dart';

// Tanpa ChargingScope halaman berjalan offline; daftarnya diberikan
// langsung supaya test tidak menyentuh jaringan.
Widget _app({List<ChargeBox>? chargeBoxes}) => MaterialApp(
  theme: AppTheme.build(),
  home: ChargeBoxPage(chargeBoxes: chargeBoxes ?? DemoData.chargeBoxes),
);

void main() {
  group('Pilih Charge Box', () {
    testWidgets('menampilkan judul dan daftar dummy', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Pilih Charge Box'), findsOneWidget);
      expect(
        find.text('Pastikan sama dengan nomor tempat parkir'),
        findsOneWidget,
      );
      expect(find.text('01'), findsOneWidget);
      expect(find.text('CS AC Charger'), findsWidgets);
    });

    testWidgets('charge box nomor 03 ditandai tidak tersedia', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Tidak Tersedia'), findsOneWidget);
    });

    testWidgets('daftar kosong tidak membuat halaman gagal render', (
      tester,
    ) async {
      await tester.pumpWidget(_app(chargeBoxes: const []));
      await tester.pumpAndSettle();

      expect(find.text('Pilih Charge Box'), findsOneWidget);
      expect(find.text('01'), findsNothing);
    });

    testWidgets('menekan kartu membuka bottom sheet Daftar Konektor', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Nomor 04 adalah charge box DC dengan dua konektor.
      await tester.tap(find.text('04'));
      await tester.pumpAndSettle();

      expect(find.text('Daftar Konektor'), findsOneWidget);
      expect(find.text('04 · CS DC Charger'), findsOneWidget);
      expect(find.text('Gun 1'), findsOneWidget);
      expect(find.text('Gun 2'), findsOneWidget);
      expect(find.text('CCS2 · DC'), findsNWidgets(2));
      expect(find.text('Tersedia'), findsNWidgets(2));
      expect(find.text('Est. 15 menit'), findsOneWidget);
    });
  });

  group('Data dummy', () {
    test('ada enam charge box, satu di antaranya tidak tersedia', () {
      expect(DemoData.chargeBoxes, hasLength(6));
      expect(
        DemoData.chargeBoxes.where((b) => !b.isAvailable).map((b) => b.badge),
        ['03'],
      );
    });

    test('badge diberi nol di depan', () {
      expect(DemoData.chargeBoxes.first.badge, '01');
      expect(DemoData.chargeBoxes.last.badge, '06');
    });

    test('charge box DC punya dua konektor bernama Gun 1 dan Gun 2', () {
      final dc = DemoData.chargeBoxes[3];

      expect(dc.connectorLabel, '2 Konektor');
      expect(dc.connectors[0].status, ConnectorStatus.available);
      expect(dc.connectors[1].status, ConnectorStatus.available);
      expect(dc.connectors[1].estimatedMinutes, 15);
      expect(dc.isAvailable, isTrue);
    });

    test('pilihan kWh offline mengikuti bentuk /list-kwh', () {
      expect(DemoData.kwhOptions, [10, 20, 30]);
    });

    /// Harga tiruan hanya dipakai saat tidak ada ChargingScope; di
    /// aplikasi sungguhan semua angkanya dari `POST /count-kwh`.
    test('harga tiruan naik seiring kWh yang dipilih', () {
      final murah = DemoData.priceFor(10);
      final mahal = DemoData.priceFor(30);

      expect(murah.kwh, 10);
      expect(mahal.rpTotal, greaterThan(murah.rpTotal));
      expect(murah.rpPerKwh, mahal.rpPerKwh);
    });
  });
}
