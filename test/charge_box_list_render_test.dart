import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/theme/app_theme.dart';

/// Persis bentuk /list yang dikeluhkan: dua charge box, yang pertama
/// hanya punya konektor "Preparing".
final _boxes = [
  ChargeBox.fromJson(const {
    'id': 'SIM-123',
    'connectors': [
      {'id': 1, 'status': 'Preparing', 'errorCode': 'NoError'},
    ],
  }, number: 1),
  ChargeBox.fromJson(const {
    'id': 'SIM-456',
    'connectors': [
      {'id': 1, 'status': 'Preparing', 'errorCode': 'NoError'},
      {'id': 2, 'status': 'Available', 'errorCode': 'NoError'},
    ],
  }, number: 2),
];

void main() {
  testWidgets('dua charge box dari /list keduanya tampil', (tester) async {
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
    expect(find.text('SIM-123'), findsOneWidget);
    expect(find.text('SIM-456'), findsOneWidget);
  });
}
