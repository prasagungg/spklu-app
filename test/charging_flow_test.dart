import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';
import 'package:kossotrik/widgets/primary_button.dart';

/// Halaman dengan hitung mundur dan spinner memakai timer berulang,
/// sehingga pumpAndSettle tidak akan pernah selesai. Dipakai pump
/// berdurasi tetap untuk halaman-halaman tersebut.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('alur lengkap: charge box sampai pengisian selesai',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        // Tanpa ChargingScope, alur berjalan offline: /start dan /stop
        // dilewati dan energi disimulasikan lokal.
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Pilih Charge Box — pilih nomor 04 (DC, dua konektor).
    expect(find.text('Pilih Charge Box'), findsOneWidget);
    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();

    // 2. Daftar Konektor — pilih konektor yang tersedia.
    expect(find.text('Daftar Konektor'), findsOneWidget);
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();

    // 3. Pilih Nominal — Rp50.000 sudah terpilih sejak awal.
    expect(find.text('Pilih Nominal'), findsOneWidget);
    expect(find.text('Rincian Harga'), findsOneWidget);
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();

    // 4. Konfirmasi Pengisian.
    expect(find.text('Konfirmasi Pengisian'), findsOneWidget);
    expect(find.text('Charge Box'), findsOneWidget);
    expect(find.text('Total Pembayaran'), findsOneWidget);
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);

    // 5. Pembayaran Kartu — statis, dimajukan lewat tombol simulasi.
    expect(find.text('Pembayaran'), findsOneWidget);
    expect(find.text('Menunggu Kartu'), findsOneWidget);
    expect(find.text('Kode Sesi'), findsOneWidget);
    await tester.tap(find.text('Bayar (Simulasi)'));
    await settle(tester);

    // 6. Pembayaran Berhasil.
    expect(find.text('Pembayaran Berhasil'), findsOneWidget);
    expect(find.text('Detail Transaksi'), findsOneWidget);
    expect(find.text('EV Charging'), findsOneWidget);
    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);

    // 7. Hubungkan Konektor — tombol utama nonaktif saat menunggu.
    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(find.text('Menunggu konektor terdeteksi...'), findsOneWidget);

    // 8. Setelah jeda deteksi, berubah jadi Konektor Terhubung.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Konektor Terhubung'), findsOneWidget);
    expect(
      find.textContaining('Konektor berhasil terdeteksi'),
      findsOneWidget,
    );

    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);

    // 9. Langsung ke layar status, bukan interstitial Pengisian Dimulai.
    expect(find.text('Sedang Mengisi'), findsOneWidget);
    expect(find.text('Energi tersalur'), findsOneWidget);
    expect(find.text('Pengisian Dimulai'), findsNothing);

    // 10. Energi bertambah seiring waktu — inilah "cek status".
    // Di bawah 1 kWh dipakai tiga desimal agar pergerakannya terlihat.
    expect(find.text('0,000 kWh'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0,400 kWh'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0,800 kWh'), findsOneWidget);

    // 11. Akhiri pengisian -> layar konfirmasi.
    await tester.tap(find.text('Akhiri Pengisian'));
    await settle(tester);
    expect(find.text('Akhiri Pengisian?'), findsOneWidget);
    expect(find.text('Pembayaran Awal'), findsOneWidget);
    expect(
      find.text('Nilai akhir dihitung setelah charger berhenti.'),
      findsOneWidget,
    );

    // 12. Konfirmasi -> Pengisian Selesai dengan rincian akhir.
    await tester.tap(find.text('Ya, Akhiri Pengisian'));
    await settle(tester);
    expect(find.text('Pengisian Selesai'), findsOneWidget);
    expect(find.text('Energi Tersalur'), findsOneWidget);
    expect(find.text('Sisa Pembayaran'), findsOneWidget);
    expect(
      find.text('Lepas dan kembalikan konektor ke tempatnya'),
      findsOneWidget,
    );

    // 13. Kembali ke halaman awal.
    await tester.tap(find.text('Kembali ke Halaman Awal'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih Charge Box'), findsOneWidget);
  });

  testWidgets('Lanjut Pengisian membatalkan penghentian sesi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        // Tanpa ChargingScope, alur berjalan offline: /start dan /stop
        // dilewati dan energi disimulasikan lokal.
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);
    await tester.tap(find.text('Bayar (Simulasi)'));
    await settle(tester);
    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);

    await tester.tap(find.text('Akhiri Pengisian'));
    await settle(tester);
    expect(find.text('Akhiri Pengisian?'), findsOneWidget);

    await tester.tap(find.text('Lanjut Pengisian'));
    await settle(tester);

    // Kembali ke layar status, dan penghitungan energi jalan lagi.
    expect(find.text('Sedang Mengisi'), findsOneWidget);
    expect(find.text('Pengisian Selesai'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('kWh'), findsOneWidget);
  });

  testWidgets('tombol Mulai Pengisian nonaktif sebelum konektor terdeteksi',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        // Tanpa ChargingScope, alur berjalan offline: /start dan /stop
        // dilewati dan energi disimulasikan lokal.
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);
    await tester.tap(find.text('Bayar (Simulasi)'));
    await settle(tester);
    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);

    // Selama menunggu, tombol utama tidak punya handler sama sekali.
    // Dipakai .last karena rute yang ditinggalkan masih ada di pohon
    // widget selama animasi transisi.
    PrimaryButton startButton() => tester.widget<PrimaryButton>(
          find.widgetWithText(PrimaryButton, 'Mulai Pengisian').last,
        );

    expect(find.text('Hubungkan Konektor'), findsOneWidget);
    expect(startButton().onPressed, isNull);

    // Setelah konektor terdeteksi, tombol itu aktif kembali.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(startButton().onPressed, isNotNull);
  });

  testWidgets('setiap halaman selain halaman awal punya tombol Home',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        // Tanpa ChargingScope, alur berjalan offline: /start dan /stop
        // dilewati dan energi disimulasikan lokal.
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    // Halaman awal tidak perlu tombol pulang.
    expect(find.text('Pilih Charge Box'), findsOneWidget);
    expect(find.byType(HomeButton), findsNothing);

    Future<void> expectHome(String title) async {
      expect(find.text(title), findsOneWidget, reason: title);
      expect(find.byType(HomeButton), findsWidgets, reason: title);
    }

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();
    await expectHome('Pilih Nominal');

    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await expectHome('Konfirmasi Pengisian');

    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);
    await expectHome('Pembayaran');

    await tester.tap(find.text('Bayar (Simulasi)'));
    await settle(tester);
    await expectHome('Pembayaran Berhasil');

    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);
    await expectHome('Hubungkan Konektor');

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);
    await expectHome('Sedang Mengisi');

    await tester.tap(find.text('Akhiri Pengisian'));
    await settle(tester);
    await expectHome('Akhiri Pengisian?');

    await tester.tap(find.text('Ya, Akhiri Pengisian'));
    await settle(tester);
    await expectHome('Pengisian Selesai');
  });

  testWidgets('tombol Home mengembalikan ke halaman awal dari mana pun',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        // Tanpa ChargingScope, alur berjalan offline: /start dan /stop
        // dilewati dan energi disimulasikan lokal.
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tersedia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);
    expect(find.text('Pembayaran'), findsOneWidget);

    await tester.tap(find.byType(HomeButton).last);
    await tester.pumpAndSettle();

    expect(find.text('Pilih Charge Box'), findsOneWidget);
    expect(find.text('Pembayaran'), findsNothing);
  });
}
