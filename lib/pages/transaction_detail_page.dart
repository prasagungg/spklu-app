import 'package:flutter/material.dart';

import '../data/formatters.dart';
import '../models/transaction_detail.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';

/// Rincian satu transaksi riwayat, dari
/// `POST /transaction/detail-history-transaction`.
///
/// Dibuka setelah kode sesinya benar di [TransactionCodePage]. Semua
/// angkanya dipakai apa adanya — tidak ada yang dihitung di sini, sama
/// seperti layar rincian lain.
///
/// Desainnya mengikuti kartu "Detail Transaksi" yang sudah ada di
/// halaman Pembayaran Berhasil (73:3229): kartu putih, baris
/// label-nilai, dengan baris terakhir sebagai jumlah yang ditonjolkan.
class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({super.key, required this.detail});

  final TransactionDetail detail;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Detail Transaksi',
      subtitle: detail.spkluName.isEmpty
          ? 'Rincian pengisian yang pernah dilakukan'
          : detail.spkluName,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: 'Kembali ke Halaman Awal',
            trailingAsset: 'assets/icons/ic_home_filled.svg',
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _Card(
            title: 'Charger',
            rows: [
              (label: 'Charge Box', value: detail.chargeBoxName),
              (label: 'Konektor', value: detail.connectorName),
              (label: 'Waktu', value: formatDateTime(detail.recordedAt)),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            title: 'Energi',
            rows: [
              (label: 'kWh Dibeli', value: formatKwh(detail.orderedKwh)),
              (label: 'kWh Terpakai', value: formatKwh(detail.usedKwh)),
              (label: 'Sisa kWh', value: formatKwh(detail.remainingKwh)),
              if (detail.pricePerKwh > 0)
                (
                  label: 'Tarif per kWh',
                  value: formatRupiahDecimal(detail.pricePerKwh),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            title: 'Pembayaran',
            rows: [
              (label: 'No Order', value: detail.orderId),
              if (detail.pspId.isNotEmpty)
                (label: 'Penerbit Kartu', value: detail.pspId),
              if (detail.cardNumber.isNotEmpty)
                // Backend sudah menyamarkannya; ditampilkan apa adanya.
                (label: 'Nomor Kartu', value: detail.cardNumber),
              (label: 'Total Pemakaian', value: formatRupiah(detail.usageAmount)),
              if (detail.serviceAmount != 0)
                (
                  label: 'Biaya Layanan',
                  value: formatRupiah(detail.serviceAmount),
                ),
              if (detail.idleFee != 0)
                (label: 'Denda Idle', value: formatRupiah(detail.idleFee)),
              (label: 'Sisa Pembayaran', value: formatRupiah(detail.refundAmount)),
            ],
            total: (label: 'Pembayaran Awal', amount: detail.paidAmount),
          ),
          const SizedBox(height: 16),
          const NoticeBar(
            text: 'Rincian ini datang langsung dari server SPKLU.',
          ),
        ],
      ),
    );
  }
}

/// Kartu putih berisi judul, garis, lalu baris label-nilai.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.rows, this.total});

  final String title;
  final List<({String label, String value})> rows;

  /// Baris yang ditonjolkan di bawah, bila ada.
  final ({String label, int amount})? total;

  @override
  Widget build(BuildContext context) {
    final highlight = total;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.cardTitle),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: AppColors.borderAlt),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            DetailRow(
              label: rows[i].label,
              value: rows[i].value,
              muted: true,
            ),
          ],
          if (highlight != null) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.totalRowGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      highlight.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.title,
                      ),
                    ),
                  ),
                  Text(
                    formatRupiah(highlight.amount),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
