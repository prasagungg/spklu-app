import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/pages/session_verification_page.dart';
import 'package:kossotrik/theme/app_theme.dart';

Future<bool?> _open(WidgetTester tester) async {
  bool? result;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => const SessionVerificationPage(),
              ),
            );
          },
          child: const Text('buka'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _press(WidgetTester tester, String digit) async {
  final key = find.widgetWithText(InkWell, digit).last;
  await tester.ensureVisible(key);
  await tester.pump();
  await tester.tap(key);
  await tester.pump();
}

Future<void> _tapVerify(WidgetTester tester) async {
  final button = find.widgetWithText(InkWell, 'Verifikasi');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Verifikasi mati sampai dua digit terisi', (tester) async {
    await _open(tester);

    expect(find.text('Verifikasi Sesi'), findsOneWidget);
    expect(find.text('Masukkan 2 digit kode sesi'), findsOneWidget);

    await _press(tester, '0');
    // Satu digit belum cukup — halaman tidak boleh tertutup.
    await _tapVerify(tester);
    expect(find.text('Verifikasi Sesi'), findsOneWidget);
  });

  testWidgets('kode benar menutup halaman dengan true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const SessionVerificationPage(),
                ),
              );
            },
            child: const Text('buka'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await _press(tester, '0');
    await _press(tester, '0');
    await _tapVerify(tester);

    expect(result, isTrue);
    expect(find.text('Verifikasi Sesi'), findsNothing);
  });

  testWidgets('kode salah mengosongkan isian dan memberi tahu', (tester) async {
    await _open(tester);

    await _press(tester, '1');
    await _press(tester, '2');
    await _tapVerify(tester);

    expect(find.text('Verifikasi Sesi'), findsOneWidget);
    expect(find.text('Kode sesi salah, coba lagi'), findsOneWidget);
    // Isian dikosongkan, jadi angka 1 dan 2 hanya tersisa di keypad.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tombol hapus menghapus digit terakhir', (tester) async {
    await _open(tester);

    await _press(tester, '1');
    await _press(tester, '2');
    // Dua digit terisi: angka 1 muncul di kotak dan di keypad.
    expect(find.text('1'), findsNWidgets(2));

    final erase = find.byKey(SessionVerificationPage.eraseKey);
    await tester.ensureVisible(erase);
    await tester.pump();
    await tester.tap(erase);
    await tester.pump();

    // Digit terakhir (2) hilang dari kotak.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('Kembali menutup halaman dengan false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const SessionVerificationPage(),
                ),
              );
            },
            child: const Text('buka'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
