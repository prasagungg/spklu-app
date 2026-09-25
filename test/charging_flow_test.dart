import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/card_reader_scope.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/pages/charging_started_page.dart';
import 'package:kossotrik/pages/charging_status_page.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/page_scaffold.dart';
import 'package:kossotrik/widgets/primary_button.dart';

import 'fake_card_reader.dart';
import 'flow_helpers.dart';

/// Halaman dengan hitung mundur dan spinner memakai timer berulang,
/// sehingga pumpAndSettle tidak akan pernah selesai. Dipakai pump
/// berdurasi tetap untuk halaman-halaman tersebut.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Membangun alur dari halaman Pilih Charge Box dan mengembalikan
/// pembaca kartu palsunya, supaya test bisa meniru kartu ditempelkan.
///
/// Tanpa ChargingScope, alur berjalan offline: /start dan /stop
/// dilewati dan energi disimulasikan lokal.
Future<FakeCardReader> pumpFlow(WidgetTester tester) async {
  final reader = FakeCardReader();

  await tester.pumpWidget(
    CardReaderScope(
      reader: reader,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: ChargeBoxPage(chargeBoxes: DemoData.chargeBoxes),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return reader;
}

/// Layar pemantauan dengan sesi demo, dipompa langsung.
///
/// Tanpa ChargingScope halaman ini menyimulasikan kenaikan kWh sendiri,
/// jadi cukup untuk menguji perilaku layarnya.
///
/// Memakai [settle], bukan pumpAndSettle: riak cairan pada gauge
/// baterai berputar terus, jadi pohon widgetnya tidak pernah diam.
Future<void> pumpStatus(WidgetTester tester) async {
  final box = DemoData.chargeBoxes[3];

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: ChargingStatusPage(
        session: ChargingSession.fromOrder(
          chargeBox: box,
          connector: box.connectors.first,
          order: DemoData.orderFor(DemoData.priceFor(10)),
          now: DateTime(2026),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('alur lengkap: charge box sampai pengisian selesai', (
    tester,
  ) async {
    final reader = await pumpFlow(tester);

    // 1. Pilih Charge Box — pilih nomor 04 (DC, dua konektor).
    expect(find.text('Pilih Charge Box'), findsOneWidget);
    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();

    // 2. Daftar Konektor — pilih konektor yang tersedia.
    expect(find.text('Daftar Konektor'), findsOneWidget);
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);

    // 3. Pilih kWh — tidak ada yang tercentang sejak awal, jadi
    // rincian harga baru muncul setelah salah satu ditekan.
    expect(find.text('Pilih kWh'), findsOneWidget);
    expect(find.text('Rincian Harga'), findsNothing);
    expect(
      tester
          .widget<PrimaryButton>(
            find.widgetWithText(PrimaryButton, 'Lanjutkan'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(find.text('Rincian Harga'), findsOneWidget);
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();

    // 4. Konfirmasi Pengisian.
    expect(find.text('Konfirmasi Pengisian'), findsOneWidget);
    expect(find.text('Charge Box'), findsOneWidget);
    expect(find.text('Total Pembayaran'), findsOneWidget);
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);

    // 5. Pembayaran Kartu — tidak ada tombol bayar; yang memajukan
    // alur adalah kartu e-Money yang ditempelkan.
    expect(find.text('Pembayaran'), findsOneWidget);
    expect(find.text('Menunggu Kartu'), findsOneWidget);
    expect(find.text('Kode Sesi'), findsOneWidget);
    // Kartu e-Money ditempelkan — inilah yang memajukan alur sekarang.
    reader.tap();
    await settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));

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
    expect(find.textContaining('Konektor berhasil terdeteksi'), findsOneWidget);

    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);

    // 9. Kode sesi dari order ditunjukkan — inilah yang diperlukan
    // pengguna untuk kembali mengakhiri sesinya.
    expect(find.text('Pengisian Dimulai'), findsOneWidget);
    expect(find.text('Simpan Kode Sesi Anda'), findsOneWidget);
    expect(find.text('00'), findsOneWidget);

    // Angkanya harus benar-benar di tengah kartunya. Kartu itu sebuah
    // Stack, dan anak yang tidak diposisikan menempel ke kiri kalau
    // lebarnya tidak direntangkan — cacat yang tidak kelihatan dari
    // teks yang ditemukan, hanya dari letaknya.
    final card = tester.getRect(find.byType(SessionCodeCard));
    expect(
      tester.getCenter(find.text('00')).dx,
      moreOrLessEquals(card.center.dx, epsilon: 0.5),
    );

    // 10. Pulang lewat tombol Home — layar tunggu tidak punya
    //     tombol aksi, dan biasanya ia berpindah sendiri.
    //
    // Membuka sesinya lagi butuh konektor yang melapor "sedang
    // mengisi"; daftar dummy di mode offline selalu "tersedia", jadi
    // bagian itu diuji di test yang memakai backend tiruan
    // (app_wiring_test dan final_energy_test).
    // Transisi rute masih mengabaikan sentuhan beberapa frame.
    await settle(tester);
    await tester.tap(find.byType(HomeButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Pilih Charge Box'), findsOneWidget);
  });

  /// Layar pemantauan dan penghentian, dipompa langsung karena mode
  /// offline tidak bisa melaporkan konektor yang sedang mengisi.
  testWidgets('memantau lalu mengakhiri pengisian', (tester) async {
    await pumpStatus(tester);

    expect(find.text('Sedang Mengisi'), findsOneWidget);
    expect(find.text('Energi tersalur'), findsOneWidget);

    // Energi bertambah seiring waktu — inilah "cek status".
    // Angkanya ditampilkan apa adanya, tanpa desimal yang dipaksakan.
    expect(find.text('0 kWh'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0,4 kWh'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0,8 kWh'), findsOneWidget);

    // Akhiri pengisian -> verifikasi kode sesi -> Pengisian Selesai.
    await endCharging(tester);
    await settle(tester);
    expect(find.text('Pengisian Selesai'), findsOneWidget);
    expect(find.text('Energi Tersalur'), findsOneWidget);
    expect(find.text('Sisa Pembayaran'), findsOneWidget);
    expect(
      find.text('Lepas dan kembalikan konektor ke tempatnya'),
      findsOneWidget,
    );
  });

  testWidgets('Pengisian Dimulai berpindah sendiri ke layar pemantauan', (
    tester,
  ) async {
    final box = DemoData.chargeBoxes[3];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargingStartedPage(
          session: ChargingSession.fromOrder(
            chargeBox: box,
            connector: box.connectors.first,
            order: DemoData.orderFor(DemoData.priceFor(10)),
            now: DateTime(2026, 9, 16, 18, 40, 39),
          ),
          // Produksi mengacak 2-4 detik; test menentukannya supaya
          // hasilnya tidak bergantung pada angka acak.
          waitFor: const Duration(seconds: 3),
        ),
      ),
    );
    await settle(tester);

    // Kode sesi masih ditunjukkan selama menunggu.
    expect(find.text('Pengisian Dimulai'), findsOneWidget);
    expect(find.text('Simpan Kode Sesi Anda'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    // Transisi rute perlu beberapa frame lagi sebelum layar tunggu
    // benar-benar lepas dari pohon widget.
    await settle(tester);

    expect(find.text('Sedang Mengisi'), findsOneWidget);
    // Menggantikan layar tunggu, bukan menumpuk di atasnya.
    expect(find.text('Pengisian Dimulai'), findsNothing);
  });

  testWidgets(
    'Akhiri Pengisian belum menghentikan apa pun sebelum kode diisi',
    (tester) async {
      await pumpStatus(tester);

      await tester.tap(find.text('Akhiri Pengisian'));
      await settle(tester);

      // Yang muncul keypad, bukan rincian akhir.
      expect(find.text('Verifikasi Sesi'), findsOneWidget);
      expect(find.text('Pengisian Selesai'), findsNothing);
    },
  );

  testWidgets('Kembali dari Verifikasi Sesi membatalkan penghentian', (
    tester,
  ) async {
    await pumpStatus(tester);

    await tester.tap(find.text('Akhiri Pengisian'));
    await settle(tester);
    expect(find.text('Verifikasi Sesi'), findsOneWidget);

    await tester.tap(find.text('Kembali'));
    await settle(tester);

    // Kembali ke layar status, dan penghitungan energi jalan lagi.
    expect(find.text('Sedang Mengisi'), findsOneWidget);
    expect(find.text('Pengisian Selesai'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('kWh'), findsOneWidget);
  });

  testWidgets('tombol Mulai Pengisian nonaktif sebelum konektor terdeteksi', (
    tester,
  ) async {
    final reader = await pumpFlow(tester);

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);
    // Kartu e-Money ditempelkan — inilah yang memajukan alur sekarang.
    reader.tap();
    await settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
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

  testWidgets('setiap halaman selain halaman awal punya tombol Home', (
    tester,
  ) async {
    final reader = await pumpFlow(tester);

    // Halaman awal tidak perlu tombol pulang.
    expect(find.text('Pilih Charge Box'), findsOneWidget);
    expect(find.byType(HomeButton), findsNothing);

    Future<void> expectHome(String title) async {
      expect(find.text(title), findsOneWidget, reason: title);
      expect(find.byType(HomeButton), findsWidgets, reason: title);
    }

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);
    await expectHome('Pilih kWh');

    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await expectHome('Konfirmasi Pengisian');

    await tester.tap(find.text('Konfirmasi & Bayar'));
    await settle(tester);
    await expectHome('Pembayaran');

    // Kartu e-Money ditempelkan — inilah yang memajukan alur sekarang.
    reader.tap();
    await settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await expectHome('Pembayaran Berhasil');

    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);
    await expectHome('Hubungkan Konektor');

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('Mulai Pengisian'));
    await settle(tester);
    await expectHome('Pengisian Dimulai');
  });

  testWidgets('halaman pengisian juga punya tombol Home', (tester) async {
    await pumpStatus(tester);

    Future<void> expectHome(String title) async {
      expect(find.text(title), findsOneWidget, reason: title);
      expect(find.byType(HomeButton), findsWidgets, reason: title);
    }

    await expectHome('Sedang Mengisi');

    await endCharging(tester);
    await settle(tester);
    await expectHome('Pengisian Selesai');
  });

  testWidgets('tombol Home mengembalikan ke halaman awal dari mana pun', (
    tester,
  ) async {
    await pumpFlow(tester);

    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10'));
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
