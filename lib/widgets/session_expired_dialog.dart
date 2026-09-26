import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../models/charging_detail.dart';
import '../models/charging_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';
import 'price_breakdown.dart';
import 'primary_button.dart';

/// Modal "Waktu Sesi Habis".
///
/// Muncul saat hitung mundur mencapai 00:00 **setelah pembayaran** —
/// pengguna sudah membayar tetapi konektornya tidak pernah terpasang.
/// Isinya sama dengan halaman "Pengisian Selesai": pengguna berhak tahu
/// uangnya jadi apa, bukan dipulangkan diam-diam.
///
/// Judulnya bukan "Pengisian Selesai" karena pengisiannya memang tidak
/// pernah terjadi.
///
/// Angkanya diambil dari `POST /transaction/charging/detail`, sumber
/// yang sama dengan halaman Pengisian Selesai. Bila ordernya tidak bisa
/// dibaca, yang dipakai angka yang sudah diketahui sesi — lebih baik
/// daripada layar kosong.
Future<void> showSessionExpiredDialog(
  BuildContext context, {
  required ChargingSession session,
}) async {
  final repository = ChargingScope.maybeOf(context)?.repository;

  ChargingDetail? detail;
  if (repository != null && session.orderId.isNotEmpty) {
    try {
      final result = await repository.fetchChargingDetail(
        orderId: session.orderId,
      );
      if (result.orderId.isNotEmpty) detail = result;
    } on Object catch (e) {
      debugPrint('[FLOW] Rincian sesi kedaluwarsa gagal dibaca: $e');
    }
  }

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    // Ditutup lewat tombolnya saja.
    barrierDismissible: false,
    builder: (_) => _SessionExpiredDialog(session: session, detail: detail),
  );
}

class _SessionExpiredDialog extends StatelessWidget {
  const _SessionExpiredDialog({required this.session, required this.detail});

  final ChargingSession session;
  final ChargingDetail? detail;

  @override
  Widget build(BuildContext context) {
    // Kabelnya tidak pernah terpasang, jadi tanpa jawaban backend
    // energinya nol dan seluruh pembayarannya menjadi sisa.
    final energyKwh = detail?.usedKwh ?? 0;
    final paid = detail?.paidAmount ?? session.paidAmount;
    final usage = detail?.usageAmount ?? 0;
    final refund = detail?.refundAmount ?? paid;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.cardShadow,
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AssetSlot(
                'assets/images/ic_session_lock.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 12),
              const Text(
                'Waktu Sesi Habis',
                textAlign: TextAlign.center,
                style: AppTheme.sheetTitle,
              ),
              const SizedBox(height: 4),
              const Text(
                'Pengisian belum dimulai sampai batas waktu yang ditentukan.'
                ' Berikut rincian sesi Anda.',
                textAlign: TextAlign.center,
                style: AppTheme.pageSubtitle,
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.borderAlt),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DetailRow(
                      label: 'Energi Tersalur',
                      value: formatEnergy(energyKwh),
                      muted: true,
                    ),
                    const SizedBox(height: 8),
                    if (paid != null) ...[
                      DetailRow(
                        label: 'Pembayaran Awal',
                        value: formatRupiah(paid),
                        muted: true,
                      ),
                      const SizedBox(height: 8),
                      DetailRow(
                        label: 'Total Pemakaian',
                        value: formatRupiah(usage),
                        muted: true,
                      ),
                      const SizedBox(height: 8),
                      DetailRow(
                        label: 'Sisa Pembayaran',
                        value: formatRupiah(refund ?? 0),
                        muted: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Kembali ke Halaman Awal',
                trailingAsset: 'assets/icons/ic_home_filled.svg',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
