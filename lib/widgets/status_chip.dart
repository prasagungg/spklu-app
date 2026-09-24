import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';

/// Pil status: px 6, py 2, radius 100, teks Inter Medium.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.fontSize = 12,
  });

  const StatusChip.available({super.key})
      : label = 'Tersedia',
        background = AppColors.availableBg,
        foreground = AppColors.availableFg,
        fontSize = 12;

  const StatusChip.inUse({super.key})
      : label = 'Sedang Digunakan',
        background = AppColors.inUseBg,
        foreground = AppColors.inUseFg,
        fontSize = 12;

  /// Sedang dipesan orang lain, belum sampai pembayaran.
  const StatusChip.reserved({super.key})
      : label = 'Dipesan',
        background = AppColors.infoTileBg,
        foreground = AppColors.description,
        fontSize = 12;

  /// Ordernya sudah dibuat, tagihannya belum dibayar.
  const StatusChip.awaitingPayment({super.key})
      : label = 'Menunggu Pembayaran',
        background = AppColors.inUseBg,
        foreground = AppColors.inUseFg,
        fontSize = 12;

  /// Di kartu charge box chip ini sedikit lebih kecil (10px).
  const StatusChip.unavailable({super.key})
      : label = 'Tidak Tersedia',
        background = AppColors.unavailableBg,
        foreground = AppColors.unavailableFg,
        fontSize = 10;

  final String label;
  final Color background;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTheme.chipLabel.copyWith(
          fontSize: fontSize,
          color: foreground,
        ),
      ),
    );
  }
}

/// Tombol bundar biru muda — dipakai untuk refresh, chevron, dan close.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.asset,
    required this.onTap,
    this.size = 36,
    this.iconSize = 20,
    this.showBorder = true,
  });

  final String asset;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
        border: showBorder ? Border.all(color: Colors.white) : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: AssetSlot(asset, width: iconSize, height: iconSize),
          ),
        ),
      ),
    );
  }
}
