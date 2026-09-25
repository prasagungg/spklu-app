import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';

/// Tombol utama (70:2308): tinggi 48, radius 12, gradient vertikal,
/// dengan ikon di dalam lingkaran semi-transparan.
///
/// Saat dinonaktifkan gradiennya diganti warna solid #B2BDCE, mengikuti
/// tombol "Mulai Pengisian" pada frame Hubungkan Konektor (73:3530).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailingAsset = 'assets/icons/ic_arrow_right.svg',
  });

  final String label;
  final VoidCallback? onPressed;

  /// Ikon di ujung kanan. Null berarti tanpa ikon.
  final String? trailingAsset;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? AppColors.ctaGradient : null,
        color: enabled ? null : AppColors.buttonDisabled,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.buttonLabel.copyWith(color: Colors.white),
                  ),
                ),
                if (trailingAsset != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: AssetSlot(trailingAsset!, width: 18, height: 18),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol sekunder bergaris biru (70:2312), tinggi 48, radius 12.
/// Opsional dengan ikon di sebelah label, seperti tombol "Bantuan"
/// pada frame Hubungkan Konektor (73:3584).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingAsset,
    this.trailingAsset,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Ikon sebelum label, mis. panah kiri pada tombol "Kembali"
  /// di halaman Verifikasi Sesi (73:4953).
  final String? leadingAsset;

  final String? trailingAsset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ikon ikut warna label. Sebagian aset digambar putih untuk
            // tombol utama yang latarnya biru; dipasang apa adanya di
            // sini, ia hilang di atas tombol putih.
            if (leadingAsset != null) ...[
              AssetSlot(
                leadingAsset!,
                width: 24,
                height: 24,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.buttonLabel.copyWith(color: AppColors.primary),
              ),
            ),
            if (trailingAsset != null) ...[
              const SizedBox(width: 8),
              AssetSlot(
                trailingAsset!,
                width: 28,
                height: 28,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tombol merah solid "Ya, Akhiri Pengisian" (73:5089).
class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : AppColors.dangerGradient,
        color: onPressed == null ? AppColors.buttonDisabled : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                style: AppTheme.buttonLabel.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol bergaris merah "Akhiri Pengisian" (73:5034).
class DangerOutlineButton extends StatelessWidget {
  const DangerOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.dangerBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: AppTheme.buttonLabel.copyWith(color: AppColors.dangerText),
        ),
      ),
    );
  }
}

/// Bilah tombol bawah berlatar putih (70:2307): padding 16, gap 12.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.children,
    this.opaque = true,
  });

  final List<Widget> children;

  /// Halaman dengan ilustrasi penuh memakai latar transparan.
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    // Inset bawah ditambahkan ke padding agar warna latarnya tetap
    // menutup area home indicator.
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      color: opaque ? AppColors.surface : null,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: children[i]),
          ],
        ],
      ),
    );
  }
}
