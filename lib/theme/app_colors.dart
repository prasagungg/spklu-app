import 'package:flutter/material.dart';

/// Token warna diambil langsung dari file Figma "SPKLU Offline Mode"
/// (canvas UI UX). Sumber kebenaran tunggal — jangan tulis hex di widget.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------- Brand
  static const Color primary = Color(0xFF0769F9);
  static const Color primaryAlt = Color(0xFF095DF2);
  static const Color primarySoft = Color(0xFFE6F2FE);

  /// Badge nomor charge box.
  /// linear-gradient(135deg, #3CB9FC 0%, #1364FD 100%)
  static const LinearGradient badgeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3CB9FC), Color(0xFF1364FD)],
  );

  /// Badge saat charge box tidak tersedia.
  static const LinearGradient badgeDisabledGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBFDFD), Color(0xFFD4E1F0)],
  );

  /// Kartu nominal yang sedang dipilih.
  static const LinearGradient nominalSelectedGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0FB2FC), Color(0xFF0068F9)],
  );

  /// Tombol "Lanjutkan".
  static const LinearGradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF039DE3), Color(0xFF0068F9)],
  );

  /// Kotak ikon konektor di bottom sheet.
  static const LinearGradient connectorIconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE6F2FE), Color(0xFFF5FAFF)],
  );

  /// Baris "Total Pembayaran".
  static const LinearGradient totalRowGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFECF5FE), Color(0xFFD8EBFD)],
  );

  // ------------------------------------------------------------ Permukaan
  static const Color pageBackground = Color(0xFFEFF6FD);
  static const Color pageBackgroundPlain = Color(0xFFFAFCFD);
  static const Color surface = Colors.white;

  static const Color border = Color(0xFFE4EFF7);
  static const Color borderAlt = Color(0xFFE5F0F7);
  static const Color badgeBorder = Color(0xFFE4ECF5);
  static const Color homeIndicator = Color(0xFF808080);

  // ---------------------------------------------------------------- Teks
  static const Color title = Color(0xFF1E2B3C);
  static const Color description = Color(0xFF5F666E);
  static const Color icon = Color(0xFF556378);

  /// Nilai di kartu "Rincian Harga".
  static const Color value = Color(0xFF111947);

  /// Varian 50% opacity untuk kartu yang dinonaktifkan.
  static const Color titleDisabled = Color(0x801E2B3C);
  static const Color iconDisabled = Color(0x80556378);

  // ---------------------------------------------------------- Chip status
  static const Color availableBg = Color(0xFFDEFCEF);
  static const Color availableFg = Color(0xFF0C804D);
  static const Color inUseBg = Color(0xFFD8ECFD);
  static const Color inUseFg = Color(0xFF026FFD);
  static const Color unavailableBg = Color(0xFFFEE7E8);
  static const Color unavailableFg = Color(0xFFF54451);

  // ------------------------------------------------- Halaman lanjutan
  /// Kartu info kecil "Nominal" / "Kode Sesi".
  static const Color infoTileBg = Color(0xFFF2F9FF);
  static const Color infoTileBorder = Color(0xFFC9E2FC);

  /// Panel kaca (backdrop blur) untuk status menunggu.
  static const Color glassBg = Color(0x80E7F4FE);
  static const Color glassBgSoft = Color(0x40E7F4FE);
  static const Color glassBorder = Color(0x80C9E2FC);

  /// Tombol utama saat dinonaktifkan.
  static const Color buttonDisabled = Color(0xFFB2BDCE);

  /// Kartu kode sesi di halaman "Pengisian Dimulai".
  static const Color sessionCardBg = Color(0xFFEEF7FE);
  static const Color sessionCardBorder = Color(0xFFC4E0FC);

  /// Blok rincian biaya di halaman konfirmasi.
  /// Teks petunjuk di kotak pencarian (204:6136).
  static const Color placeholder = Color(0xFF97A3B5);

  static const Color breakdownBg = Color(0xFFECF5FE);
  static const Color breakdownTotalBg = Color(0xFFD8EBFD);

  /// Label sekunder pada Detail Transaksi.
  static const Color mutedLabel = Color(0xFF727983);

  // --------------------------------------------- Akhiri pengisian
  /// Garis tombol "Akhiri Pengisian" (73:5034).
  static const Color dangerBorder = Color(0xFFF24752);

  /// Label tombol "Akhiri Pengisian" (73:5035).
  static const Color dangerText = Color(0xFFFF1E3C);

  /// Tombol "Ya, Akhiri Pengisian" (73:5089).
  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF24752), Color(0xFFF02935)],
  );

  /// Pita informasi biru muda (73:5148, 73:5320).
  static const Color noticeBg = Color(0xFFD9ECFC);

  // ------------------------------------------------- Verifikasi sesi
  /// Garis kotak digit yang sedang aktif (73:4867).
  static const Color pinActiveBorder = Color(0xFF0455FD);

  /// Garis tombol angka pada keypad (73:4880).
  static const Color keypadBorder = Color(0xFFBFDCF5);

  /// Garis tombol hapus (73:4934).
  static const Color keypadEraseBorder = Color(0x33F54451);

  /// 0px 0px 8px rgba(245, 68, 81, 0.25) — bayangan tombol hapus.
  static const List<BoxShadow> eraseShadow = [
    BoxShadow(color: Color(0x40F54451), blurRadius: 8),
  ];

  // -------------------------------------------------------------- Shadow
  /// 0px 0px 16px rgba(138, 187, 219, 0.5)
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x808ABBDB), blurRadius: 16),
  ];

  /// 0px 0px 8px rgba(138, 187, 219, 0.25)
  static const List<BoxShadow> cardShadowSoft = [
    BoxShadow(color: Color(0x408ABBDB), blurRadius: 8),
  ];

  /// 0px 0px 8px rgba(2, 113, 249, 0.5) — kartu nominal terpilih.
  static const List<BoxShadow> selectedShadow = [
    BoxShadow(color: Color(0x800271F9), blurRadius: 8),
  ];
}
