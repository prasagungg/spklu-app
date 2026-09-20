import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fixtures.dart';

/// Dua charge box: yang pertama satu konektor, yang kedua dua.
final _boxes = [
  ChargeBox.fromJson(
    chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01'),
    number: 1,
  ),
  ChargeBox.fromJson(
    chargeBoxJson(
      id: 'CB-SMR-02',
      nama: 'CB-SMR-02',
      connectors: [
        connectorJson(id: '1', chargeBoxId: 'CB-SMR-02'),
        connectorJson(id: '2', chargeBoxId: 'CB-SMR-02', nama: 'Gun 2'),
      ],
    ),
    number: 2,
  ),
];

void main() {
  testWidgets('dua charge box dari daftar keduanya tampil', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargeBoxPage(chargeBoxes: _boxes),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChargeBoxCard), findsNWidgets(2));
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('CB-SMR-01'), findsOneWidget);
    expect(find.text('CB-SMR-02'), findsOneWidget);
  });
}
