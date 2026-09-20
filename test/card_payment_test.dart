import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/card_reader_scope.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/card_payment_page.dart';
import 'package:kossotrik/pages/payment_success_page.dart';
import 'package:kossotrik/services/card_reader.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fake_card_reader.dart';

ChargingSession _session() {
  final box = DemoData.chargeBoxes[3];

  return ChargingSession.demo(
    chargeBox: box,
    connector: box.connectors.first,
    nominal: DemoData.nominals[1],
    now: DateTime(2026, 9, 16, 18, 40, 39),
  );
}

/// Halaman dengan hitung mundur dan spinner memakai timer berulang,
/// sehingga pumpAndSettle tidak akan pernah selesai.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> pumpPayment(WidgetTester tester, FakeCardReader reader) async {
  await tester.pumpWidget(
    CardReaderScope(
      reader: reader,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: CardPaymentPage(session: _session()),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('tidak ada lagi tombol bayar', (tester) async {
    await pumpPayment(tester, FakeCardReader());

    expect(find.text('Bayar (Simulasi)'), findsNothing);
    expect(find.text('Menunggu Kartu'), findsOneWidget);
  });

  testWidgets('pembaca langsung menunggu kartu saat halaman dibuka',
      (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    expect(reader.isWaiting, isTrue);
  });

  testWidgets('tap kartu memajukan ke Pembayaran Berhasil', (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    reader.tap();
    await settle(tester);

    expect(find.byType(PaymentSuccessPage), findsOneWidget);
    expect(find.text('Pembayaran Berhasil'), findsOneWidget);
  });

  testWidgets('sesi NFC dihentikan setelah kartu diterima', (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    reader.tap();
    await settle(tester);

    expect(reader.stopCount, greaterThan(0));
    expect(reader.isWaiting, isFalse);
  });

  /// Android melaporkan kartu yang sama berulang selama masih menempel.
  /// Tap kedua tidak boleh mendorong halaman untuk kedua kalinya.
  testWidgets('kartu yang terbaca berkali-kali hanya dihitung sekali',
      (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    reader.tap();
    reader.tap();
    reader.tap();
    await settle(tester);

    // Tiga tap, satu halaman. Kalau penjaganya hilang, tiap tap
    // mendorong rute baru dan jumlahnya ikut bertambah.
    expect(find.byType(PaymentSuccessPage), findsOneWidget);
  });

  testWidgets('NFC yang dimatikan dijelaskan, bukan dibiarkan menggantung',
      (tester) async {
    await pumpPayment(
      tester,
      FakeCardReader(reportedStatus: CardReaderStatus.disabled),
    );

    expect(find.text('Menunggu Kartu'), findsNothing);
    expect(find.textContaining('NFC sedang mati'), findsOneWidget);
    expect(find.text('Periksa Lagi'), findsOneWidget);
  });

  testWidgets('perangkat tanpa NFC diberi tahu dan diarahkan ke petugas',
      (tester) async {
    await pumpPayment(
      tester,
      FakeCardReader(reportedStatus: CardReaderStatus.unsupported),
    );

    expect(find.textContaining('tidak punya pembaca NFC'), findsOneWidget);
    expect(find.text('Menunggu Kartu'), findsNothing);
  });

  testWidgets('Periksa Lagi memeriksa ulang kesiapan pembaca',
      (tester) async {
    final reader = FakeCardReader(reportedStatus: CardReaderStatus.disabled);
    await pumpPayment(tester, reader);

    await tester.tap(find.text('Periksa Lagi'));
    await settle(tester);

    // Masih mati, jadi keterangannya tetap dan halaman tidak berpindah.
    expect(find.textContaining('NFC sedang mati'), findsOneWidget);
    expect(find.byType(PaymentSuccessPage), findsNothing);
  });

  testWidgets('sesi NFC ditutup saat halaman ditinggalkan', (tester) async {
    final reader = FakeCardReader();
    await pumpPayment(tester, reader);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(reader.stopCount, greaterThan(0));
  });
}
