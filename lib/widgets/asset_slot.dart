import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// Merender asset dari Figma — PNG lewat [Image.asset], SVG lewat
/// [SvgPicture.asset]. Kalau file-nya belum ada, digambar kotak placeholder
/// bertuliskan nama file supaya jelas asset mana yang masih kurang.
class AssetSlot extends StatelessWidget {
  const AssetSlot(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.color,
    this.fit = BoxFit.contain,
  });

  final String path;
  final double? width;
  final double? height;

  /// Tint untuk ikon monokrom.
  final Color? color;
  final BoxFit fit;

  bool get _isSvg => path.toLowerCase().endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    if (_isSvg) {
      return SvgPicture.asset(
        path,
        width: width,
        height: height,
        fit: fit,
        colorFilter: color == null
            ? null
            : ColorFilter.mode(color!, BlendMode.srcIn),
        placeholderBuilder: (_) => _Placeholder(
          label: path.split('/').last,
          width: width,
          height: height,
        ),
      );
    }

    return Image.asset(
      path,
      width: width,
      height: height,
      color: color,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _Placeholder(
        label: path.split('/').last,
        width: width,
        height: height,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label, this.width, this.height});

  final String label;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
