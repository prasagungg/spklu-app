import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/env.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/pages/settings_page.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mengetuk logo [times] kali beruntun.
Future<void> tapLogo(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(PageScaffold.logKey));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle();
}

Future<void> enterPassword(WidgetTester tester, String password) async {
  await tester.enterText(find.byType(TextField), password);
  await tester.tap(find.text('Masuk'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empat ketukan belum membuka apa pun', (tester) async {
    await _pump(tester);

    await tapLogo(tester, 4);

    expect(find.text('Akses Pengaturan'), findsNothing);
  });

  testWidgets('lima ketukan meminta password', (tester) async {
    await _pump(tester);

    await tapLogo(tester, 5);

    expect(find.text('Akses Pengaturan'), findsOneWidget);
    // Belum boleh masuk sebelum passwordnya benar.
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('password benar membuka halaman Pengaturan', (tester) async {
    await _pump(tester);
    await tapLogo(tester, 5);

    await enterPassword(tester, Env.settingsPassword);

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Kelola perangkat dan pengaturan SPKLU'), findsOneWidget);
    expect(find.text('Konfigurasi SAM Card'), findsOneWidget);
    expect(find.text('Tes Transaksi'), findsOneWidget);
    expect(find.textContaining('Versi'), findsOneWidget);
  });

  testWidgets('password salah ditolak dan modalnya tetap terbuka', (
    tester,
  ) async {
    await _pump(tester);
    await tapLogo(tester, 5);

    await enterPassword(tester, 'salah');

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Password salah. Coba lagi.'), findsOneWidget);
    expect(find.text('Akses Pengaturan'), findsOneWidget);
  });

  testWidgets('Batal menutup modal tanpa membuka pengaturan', (tester) async {
    await _pump(tester);
    await tapLogo(tester, 5);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Akses Pengaturan'), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
  });

  /// Ketukan yang berjauhan adalah sentuhan biasa, bukan rangkaian.
  testWidgets('ketukan yang lewat dari jendela waktu tidak menumpuk', (
    tester,
  ) async {
    await _pump(tester);

    await tapLogo(tester, 3);
    await tester.pump(const Duration(seconds: 3));
    await tapLogo(tester, 3);

    expect(find.text('Akses Pengaturan'), findsNothing);
  });
}
