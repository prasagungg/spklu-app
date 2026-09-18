import 'package:flutter/material.dart';

import '../data/formatters.dart';
import '../models/nominal_option.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Baris label/nilai — label Regular 12, nilai SemiBold 12.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;

  /// Label abu lebih gelap, dipakai di kartu Detail Transaksi.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: muted
              ? AppTheme.rowLabel.copyWith(color: AppColors.mutedLabel)
              : AppTheme.rowLabel,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTheme.rowValue,
          ),
        ),
      ],
    );
  }
}

/// Baris total (70:2303) — radius 8, padding 8.
class TotalRow extends StatelessWidget {
  const TotalRow({super.key, required this.amount, this.solid = false});

  final int amount;

  /// Varian latar solid #D8EBFD di halaman konfirmasi (73:2732).
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: solid ? AppColors.breakdownTotalBg : null,
        gradient: solid ? null : AppColors.totalRowGradient,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Total Pembayaran',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.title,
              ),
            ),
          ),
          Text(
            formatRupiah(amount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lima baris biaya yang sama di halaman Nominal, Konfirmasi, dan
/// Pembayaran Berhasil.
class CostRows extends StatelessWidget {
  const CostRows({super.key, required this.nominal});

  final NominalOption nominal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DetailRow(label: 'Total kWh dibeli', value: formatKwh(nominal.kwh)),
        const SizedBox(height: 12),
        DetailRow(
          label: 'Biaya Listrik',
          value: formatRupiah(nominal.electricityCost),
        ),
        const SizedBox(height: 12),
        DetailRow(label: 'PBJT-TL', value: formatRupiah(nominal.pbjtTl)),
        const SizedBox(height: 12),
        DetailRow(label: 'Biaya PPN', value: formatRupiah(nominal.ppn)),
        const SizedBox(height: 12),
        DetailRow(
          label: 'Biaya Layanan',
          value: formatRupiah(nominal.serviceFee),
        ),
      ],
    );
  }
}
