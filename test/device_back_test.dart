import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/pages/nominal_page.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'flow_helpers.dart';

/// Meniru tombol/gesture kembali bawaan perangkat.
Future<void> pressDeviceBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  /// Unit ini kios: alurnya punya urutan yang harus dijaga — konektor
  /// yang dikunci perlu dilepas, perintah stop perlu kode sesi. Gesture
  /// kembali bawaan perangkat melompati semua itu.
  testWidgets('kembali perangkat tidak memindahkan halaman', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);
    expect(find.byType(NominalPage), findsOneWidget);

    await pressDeviceBack(tester);

    // Masih di halaman yang sama.
    expect(find.byType(NominalPage), findsOneWidget);
    expect(find.text('Pilih Charge Box'), findsNothing);

    // Tombol aplikasi tetap bekerja seperti biasa — PopScope hanya
    // menahan pop dari sistem, bukan Navigator.pop.
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(find.byType(NominalPage), findsNothing);
  });

  testWidgets('kembali perangkat tidak menutup daftar konektor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar Konektor'), findsOneWidget);

    await pressDeviceBack(tester);
    expect(find.text('Daftar Konektor'), findsOneWidget);
  });
}
