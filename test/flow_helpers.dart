import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';

/// Memajukan halaman yang punya timer berulang, yang membuat
/// pumpAndSettle tidak pernah selesai.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

/// Melewati halaman "Kode Sesi" yang muncul begitu konektor dipesan.
///
/// Halaman itu punya hitung mundur yang berjalan terus, jadi
/// pumpAndSettle tidak akan pernah selesai di sana.
Future<void> passSessionCode(WidgetTester tester) async {
  await settleFrames(tester);
  expect(find.text('Kode Sesi'), findsOneWidget);

  await tester.tap(find.text('Lanjutkan'));
  await settleFrames(tester);
}

/// Mengetikkan kode sesi pada keypad Verifikasi Sesi.
Future<void> enterSessionCode(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    final key = find.widgetWithText(InkWell, digit).last;
    await tester.ensureVisible(key);
    await tester.pump();
    await tester.tap(key);
    await tester.pump();
  }
  await tester.tap(find.text('Verifikasi'));
  await settleFrames(tester);
}

/// Dari halaman "Pengisian Dimulai": pulang ke daftar, buka konektornya
/// lagi, lalu masuk dengan kode sesi sampai layar pemantauan terbuka.
///
/// Inilah jalan yang dimaksud desain — kode sesi ada supaya pengguna
/// bisa kembali ke sesinya sendiri.
Future<void> reopenChargingSession(
  WidgetTester tester, {
  String code = '29',
  String badge = '01',
  String connector = 'Gun 1',
}) async {
  expect(find.text('Pengisian Dimulai'), findsOneWidget);
  expect(find.text(code), findsOneWidget);

  // Layar tunggu tidak punya tombol aksi; jalan pulang lebih awal hanya
  // lewat tombol Home di header.
  await tester.tap(find.byType(HomeButton).first);
  await tester.pumpAndSettle();

  await tester.tap(find.text(badge));
  await tester.pumpAndSettle();
  await tester.tap(find.text(connector));
  await tester.pumpAndSettle();

  await enterSessionCode(tester, code);
}

/// Dari layar "Sedang Mengisi": mengakhiri pengisian.
///
/// Perintah stop tidak terkirim saat "Akhiri Pengisian" ditekan —
/// halaman Verifikasi Sesi muncul lebih dulu, dan kode yang diketik
/// ikut dikirim bersama `/stop`.
Future<void> endCharging(WidgetTester tester, {String code = '29'}) async {
  await tester.tap(find.text('Akhiri Pengisian'));
  await settleFrames(tester);
  expect(find.text('Verifikasi Sesi'), findsOneWidget);

  await enterSessionCode(tester, code);
}
