import 'package:flutter/material.dart';

import '../data/formatters.dart';
import '../models/charging_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';

/// Frame Figma 73:5171 — "Pengisian Selesai".
class ChargingFinishedPage extends StatelessWidget {
  const ChargingFinishedPage({
    super.key,
    required this.session,
    required this.energyKwh,
  });

  final ChargingSession session;
  final double energyKwh;

  @override
  Widget build(BuildContext context) {
    final usage = session.usageCostFor(energyKwh);

    return PageScaffold(
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
          const Center(
            child: AssetSlot(
              'assets/images/finished_check.png',
              width: 180,
              height: 180,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pengisian Selesai',
            textAlign: TextAlign.center,
            style: AppTheme.pageTitle,
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.borderAlt),
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppColors.cardShadow,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DetailRow(
                  label: 'Energi Tersalur',
                  value: formatEnergy(energyKwh),
                  muted: true,
                ),
                // Sesi yang dilanjutkan tidak membawa data pembelian,
                // jadi baris pembayarannya dilewati.
                if (session.hasPurchase) ...[
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Pembayaran Awal',
                    value: formatRupiah(session.price!.rpTotal),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Total Pemakaian',
                    value: formatRupiah(usage ?? 0),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Sisa Pembayaran',
                    value: formatRupiah(session.refundFor(energyKwh) ?? 0),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const NoticeBar(
            text: 'Lepas dan kembalikan konektor ke tempatnya',
            asset: 'assets/icons/ic_connector.svg',
          ),
        ],
      ),
    );
  }
}
