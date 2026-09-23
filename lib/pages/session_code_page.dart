import 'dart:async';

import 'package:flutter/material.dart';

import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/reservation.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'nominal_page.dart';

/// Frame Figma 203:3352 — "Kode Sesi".
///
/// Muncul tepat setelah konektor dipesan lewat `POST /booked-connector`.
/// Kode sesinya datang dari pemesanan itu — pengguna mendapatkannya
/// sejak memilih nozzle, jauh sebelum membayar, dan memerlukannya untuk
/// kembali ke sesinya sendiri.
///
/// "Batalkan Transaksi" cukup menutup halaman: kembalinya pengguna ke
/// daftar charge box sudah melepas pemesanan yang ditinggalkan, lewat
/// satu jalur yang sama dengan tombol Home dan tombol kembali
/// perangkat.
class SessionCodePage extends StatefulWidget {
  const SessionCodePage({
    super.key,
    required this.chargeBox,
    required this.connector,
    required this.reservation,
  });

  final ChargeBox chargeBox;
  final Connector connector;
  final Reservation reservation;

  @override
  State<SessionCodePage> createState() => _SessionCodePageState();
}

class _SessionCodePageState extends State<SessionCodePage> {
  /// Dipakai bila backend tidak menyebut batas waktunya.
  static const _fallbackLimit = Duration(minutes: 10);

  Timer? _ticker;
  late Duration _remaining = _initialRemaining();

  Duration _initialRemaining() {
    final expiry = widget.reservation.expiredAt;
    if (expiry == null) return _fallbackLimit;

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

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NominalPage(
          chargeBox: widget.chargeBox,
          connector: widget.connector,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      backgroundColor: AppColors.pageBackgroundPlain,
      headerExtra: CountdownPill(remaining: _remaining),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _SessionCodeCard(code: widget.reservation.sessionCode),
          const SizedBox(height: 16),
          _ChosenConnectorCard(
            chargeBox: widget.chargeBox,
            connector: widget.connector,
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Lanjutkan', onPressed: _continue),
          const SizedBox(height: 16),
          DangerOutlineButton(
            label: 'Batalkan Transaksi',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Kartu kode sesi (203:3531) — putih bergaris biru, dengan panel biru
/// muda berisi angkanya.
class _SessionCodeCard extends StatelessWidget {
  const _SessionCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          const Text(
            'Kode Sesi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 124,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.breakdownBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Catat atau foto kode ini',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kode ini digunakan untuk mengenali sesi pengisian Anda.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.description,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu "Konektor yang Dipilih" (203:3548).
class _ChosenConnectorCard extends StatelessWidget {
  const _ChosenConnectorCard({
    required this.chargeBox,
    required this.connector,
  });

  final ChargeBox chargeBox;
  final Connector connector;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.infoTileBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const AssetSlot(
              'assets/icons/ic_connector_ccs2.svg',
              width: 24,
              height: 24,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Konektor yang Dipilih',
                  style: AppTheme.cardCaption.copyWith(
                    color: AppColors.description,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // "01 - CCS2 - 200 kW DC": nomor charge box, tipe
                  // konektor, lalu daya milik charge box.
                  '${chargeBox.badge} - '
                  '${connector.describeWith(chargeBox.daya)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.title,
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
