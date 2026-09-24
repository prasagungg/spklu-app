import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';

/// Hitung mundur sampai [expiresAt], berdetak sendiri tiap detik.
///
/// Batas waktunya milik pemesanan (`sessionExpired`), jadi halaman yang
/// berbeda dalam satu alur menunjukkan sisa waktu yang sama — bukan
/// sepuluh menit yang dimulai ulang tiap pindah layar.
///
/// [expiresAt] null berarti backend tidak menyebutkannya; dipakai
/// [fallback] supaya pilnya tetap ada seperti di desain.
class ExpiryCountdown extends StatefulWidget {
  const ExpiryCountdown({
    super.key,
    this.expiresAt,
    this.compact = false,
    this.fallback = const Duration(minutes: 10),
  });

  final DateTime? expiresAt;

  /// Varian kecil yang duduk sebaris dengan judul halaman (204:4690).
  final bool compact;

  final Duration fallback;

  @override
  State<ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<ExpiryCountdown> {
  Timer? _ticker;
  late Duration _remaining = _initial();

  Duration _initial() {
    final expiry = widget.expiresAt;
    if (expiry == null) return widget.fallback;

    final left = expiry.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.compact
      ? CompactCountdownPill(remaining: _remaining)
      : CountdownPill(remaining: _remaining);
}

/// Pil hitung mundur "Selesaikan dalam: 09:59" (73:2850).
class CountdownPill extends StatelessWidget {
  const CountdownPill({super.key, required this.remaining});

  final Duration remaining;

  String get _formatted {
    final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AssetSlot('assets/icons/ic_timer.svg', width: 20, height: 20),
          const SizedBox(width: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Selesaikan dalam: '),
                TextSpan(
                  text: _formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.description,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pil hitung mundur kecil yang duduk sebaris dengan judul halaman
/// (204:4690) — hanya ikon dan angkanya, tanpa kata "Selesaikan dalam".
///
/// Dipakai di halaman yang judulnya tetap terlihat, jadi pilnya tidak
/// boleh memakan satu baris sendiri.
class CompactCountdownPill extends StatelessWidget {
  const CompactCountdownPill({super.key, required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AssetSlot('assets/icons/ic_timer.svg', width: 15.5, height: 18),
          const SizedBox(width: 4),
          Text(
            '$minutes:$seconds',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.title,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel kaca untuk pesan status (73:2861, 73:3570, 73:3632).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.soft = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  /// Varian dengan latar lebih transparan, dipakai di halaman pembayaran.
  final bool soft;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: soft ? AppColors.glassBgSoft : AppColors.glassBg,
        border: Border.all(color: AppColors.glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// Panel status dengan spinner, mis. "Menunggu Kartu".
class WaitingPanel extends StatelessWidget {
  const WaitingPanel({super.key, required this.label, this.soft = false});

  final String label;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      soft: soft,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _Spinner(),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ikon spinner Figma yang diputar terus-menerus.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: const AssetSlot(
        'assets/icons/ic_spinner.svg',
        width: 24,
        height: 24,
      ),
    );
  }
}

/// Kartu kecil "Nominal" / "Kode Sesi" (73:2866).
class InfoTile extends StatelessWidget {
  const InfoTile({
    super.key,
    required this.asset,
    required this.label,
    required this.value,
  });

  final String asset;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoTileBg,
        border: Border.all(color: AppColors.infoTileBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          AssetSlot(asset, width: 28, height: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.description,
                    letterSpacing: -0.24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.title,
                    letterSpacing: -0.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sepasang [InfoTile] Nominal + Kode Sesi.
class SessionInfoRow extends StatelessWidget {
  const SessionInfoRow({
    super.key,
    required this.nominalLabel,
    required this.sessionCode,
  });

  final String nominalLabel;
  final String sessionCode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InfoTile(
            asset: 'assets/images/ic_wallet.png',
            label: 'Nominal',
            value: nominalLabel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InfoTile(
            asset: 'assets/images/ic_session_lock.png',
            label: 'Kode Sesi',
            value: sessionCode,
          ),
        ),
      ],
    );
  }
}

/// Baris rincian dengan kotak ikon di kiri (73:2624).
class IconDetailRow extends StatelessWidget {
  const IconDetailRow({
    super.key,
    required this.asset,
    required this.label,
    required this.value,
  });

  final String asset;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AssetSlot(asset, width: 20, height: 20),
        ),
        const SizedBox(width: 12),
        Text(label, style: AppTheme.rowLabel),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTheme.rowValue,
          ),
        ),
      ],
    );
  }
}

/// Teks bantuan di atas pita gradasi (73:3596).
class HintStrip extends StatelessWidget {
  const HintStrip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 69,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: AssetSlot(
              'assets/images/hint_strip.png',
              fit: BoxFit.cover,
            ),
          ),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.title,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pita informasi biru muda (73:5148, 73:5320) — radius 12, px 12, py 8.
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.text,
    this.asset = 'assets/icons/ic_info_circle_fill.svg',
  });

  final String text;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.noticeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AssetSlot(asset, width: 24, height: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.title,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
