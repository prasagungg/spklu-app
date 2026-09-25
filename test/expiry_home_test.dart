import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/card_reader_scope.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/models/order.dart';
import 'package:kossotrik/pages/card_payment_page.dart';
import 'package:kossotrik/pages/confirmation_page.dart';
import 'package:kossotrik/pages/connect_connector_page.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/session_widgets.dart';

import 'fake_card_reader.dart';

/// Sesi yang tenggatnya sudah lewat: hitung mundurnya mulai dari 00:00,
/// jadi detak pertama sudah menemukannya kedaluwarsa.
ChargingSession _expiredSession() {
  final box = DemoData.chargeBoxes[3];

  return ChargingSession.fromOrder(
    chargeBox: box,
    connector: box.connectors.first,
    order: Order(
      orderId: 'ORDER-1',
      sessionCode: '29',
      partnerReference: '81067',
      kwh: 19.5,
      rpTotal: 50000,
      sessionExpiredAt: DateTime.now().subtract(const Duration(seconds: 5)),
    ),
    now: DateTime(2026, 9, 16, 18, 40, 39),
  );
}

/// Halaman awal tiruan yang mendorong [page] di atasnya, supaya
/// kepulangan ke rute pertama bisa dilihat.
Future<void> _open(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    CardReaderScope(
      reader: FakeCardReader(),
      child: MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('Pilih Charge Box'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Pilih Charge Box'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Satu detak hitung mundur, lalu animasi kepulangannya.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('tenggat habis memulangkan ke halaman awal', () {
    testWidgets('dari Pembayaran Kartu', (tester) async {
      await _open(tester, CardPaymentPage(session: _expiredSession()));
      expect(find.text('Pembayaran'), findsWidgets);

      await _tick(tester);

      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    /// Ordernya sudah ada di tahap ini, jadi pemesanannya tidak dilepas
    /// — cukup pulang.
    testWidgets('dari Konfirmasi Pengisian', (tester) async {
      final box = DemoData.chargeBoxes[3];

      await _open(
        tester,
        ConfirmationPage(
          chargeBox: box,
          connector: box.connectors.first,
          order: Order(
            orderId: 'ORDER-1',
            sessionCode: '29',
            partnerReference: '81067',
            kwh: 19.5,
            rpTotal: 50000,
            sessionExpiredAt: DateTime.now().subtract(
              const Duration(seconds: 5),
            ),
          ),
        ),
      );
      expect(find.text('Konfirmasi Pengisian'), findsOneWidget);

      await _tick(tester);

      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    testWidgets('dari Hubungkan Konektor', (tester) async {
      await _open(tester, ConnectConnectorPage(session: _expiredSession()));
      expect(find.text('Hubungkan Konektor'), findsOneWidget);

      await _tick(tester);

      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    testWidgets('dari pil hitung mundur biasa', (tester) async {
      await _open(
        tester,
        Scaffold(
          appBar: AppBar(
            title: ExpiryCountdown(
              expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
            ),
          ),
        ),
      );

      await _tick(tester);

      expect(find.text('Pilih Charge Box'), findsOneWidget);
    });

    testWidgets('lewat onExpired bila halamannya perlu melepas pemesanan', (
      tester,
    ) async {
      var released = 0;

      await _open(
        tester,
        Scaffold(
          appBar: AppBar(
            title: ExpiryCountdown(
              expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
              onExpired: () => released++,
            ),
          ),
        ),
      );

      await _tick(tester);

      // Halamannya yang menentukan cara pulang — di sini melepas
      // pemesanan dulu, jadi pil tidak memulangkan sendiri.
      expect(released, 1);
      expect(find.text('Pilih Charge Box'), findsNothing);
    });

    testWidgets('halaman yang sudah tertutup tidak menarik pengguna keluar', (
      tester,
    ) async {
      var released = 0;
      late BuildContext pageContext;

      await _open(
        tester,
        Scaffold(
          appBar: AppBar(
            title: Builder(
              builder: (context) {
                pageContext = context;
                return ExpiryCountdown(
                  expiresAt: DateTime.now().subtract(
                    const Duration(seconds: 5),
                  ),
                  onExpired: () => released++,
                );
              },
            ),
          ),
        ),
      );

      // Tahap berikutnya dibuka sebelum tenggatnya terbaca habis.
      Navigator.of(pageContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Tahap Berikutnya')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await _tick(tester);

      expect(released, 0);
      expect(find.text('Tahap Berikutnya'), findsOneWidget);
    });
  });
}
