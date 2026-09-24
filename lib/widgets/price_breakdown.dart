import 'package:flutter/material.dart';

import '../data/formatters.dart';
import '../models/kwh_price.dart';
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

/// Rincian biaya yang sama di halaman Nominal, Konfirmasi, dan
/// Pembayaran Berhasil.
///
/// Setiap angka datang langsung dari `POST /count-kwh`. Tidak ada yang
/// dihitung di sini — termasuk biaya energi, yang sengaja tidak
/// diturunkan dari kWh dikali tarif supaya tidak pernah berselisih
/// dengan total dari backend.
class CostRows extends StatelessWidget {
  const CostRows({super.key, required this.price});

  final PriceBreakdown price;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DetailRow(label: 'Total kWh dibeli', value: formatKwh(price.kwh)),
        const SizedBox(height: 12),
        DetailRow(
          label: 'Tarif per kWh',
          value: formatRupiahDecimal(price.rpPerKwh),
        ),
        // Hanya order yang mengirim biaya energi sebagai angka
        // tersendiri; pada tahap perkiraan barisnya tidak ada.
        if (price.rpKwh != 0) ...[
          const SizedBox(height: 12),
          DetailRow(label: 'Biaya Listrik', value: formatRupiah(price.rpKwh)),
        ],
        const SizedBox(height: 12),
        // "PBJT-TL" — istilah yang dipakai desain terbaru untuk pajak
        // yang sama; backend tetap mengirimnya sebagai `rpPpj`.
        DetailRow(label: 'PBJT-TL', value: formatRupiah(price.rpPpj)),
        const SizedBox(height: 12),
        DetailRow(label: 'Biaya PPN', value: formatRupiah(price.rpPpn)),
        for (final row in price.extraCharges) ...[
          const SizedBox(height: 12),
          DetailRow(label: row.label, value: formatRupiah(row.amount)),
        ],
      ],
    );
  }
}
