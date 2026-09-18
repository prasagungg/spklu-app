import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Skala teks mengikuti Figma. Semua Inter; ukuran dalam px desain 360dp.
class AppTheme {
  const AppTheme._();

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.pageBackground,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.title,
        displayColor: AppColors.title,
      ),
    );
  }

  /// "Pilih Charge Box" — Inter Bold 24.
  static const TextStyle pageTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.title,
  );

  /// "Pastikan sama dengan nomor tempat parkir" — Inter Regular 12.
  static const TextStyle pageSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.description,
  );

  /// "Daftar Konektor" — Inter SemiBold 20, line-height 1.5.
  static const TextStyle sheetTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.title,
    height: 1.5,
  );

  /// "04 · CS DC Charger" — Inter Regular 14.
  static const TextStyle sheetSubtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.description,
  );

  /// Judul kartu — Inter SemiBold 16.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.title,
  );

  /// "1 Konektor" — Inter Regular 12.
  static const TextStyle cardCaption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.icon,
  );

  /// Nomor badge — Inter Bold 20.
  static const TextStyle badgeNumber = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// Chip status — Inter Medium.
  static const TextStyle chipLabel = TextStyle(fontWeight: FontWeight.w500);

  /// Label baris rincian — Inter Regular 12.
  static const TextStyle rowLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.description,
  );

  /// Nilai baris rincian — Inter SemiBold 12.
  static const TextStyle rowValue = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.value,
  );

  /// Label tombol — Inter SemiBold 16.
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  /// Nominal di kartu — Inter Bold 16, tracking -0.32.
  static const TextStyle nominalLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.32,
  );
}
