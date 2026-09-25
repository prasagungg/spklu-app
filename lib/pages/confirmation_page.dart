import 'package:flutter/material.dart';

import '../data/formatters.dart';
import '../models/charge_box.dart';
import '../models/charging_session.dart';
import '../models/connector.dart';
import '../models/order.dart';
import '../theme/app_colors.dart';
import '../widgets/cancel_transaction.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'card_payment_page.dart';

/// Frame Figma 73:2531 — "Konfirmasi Pengisian".
class ConfirmationPage extends StatelessWidget {
  const ConfirmationPage({
    super.key,
    required this.chargeBox,
    required this.connector,
    required this.order,
  });

  final ChargeBox chargeBox;
  final Connector connector;
  final Order order;

  void _confirm(BuildContext context) {
    final session = ChargingSession.fromOrder(
      chargeBox: chargeBox,
      connector: connector,
      order: order,
      now: DateTime.now(),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardPaymentPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Konfirmasi Pengisian',
      subtitle: 'Pastikan detail pengisian sudah sesuai sebelum melanjutkan.',
      // Ordernya sudah dibuat `push-order` dan punya tenggat; tanpa pil
      // di sini pengguna tidak tahu waktunya habis, dan penekanan
      // "Konfirmasi & Bayar" cuma dijawab kode 22 oleh backend.
      //
      // Pemesanannya tidak dilepas saat tenggatnya habis: sejak order
      // ada, nasib konektornya ditentukan order itu.
      headerExtra: ExpiryCountdown(expiresAt: order.sessionExpiredAt),
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        children: [
          PrimaryButton(
            label: 'Konfirmasi & Bayar',
            trailingAsset: 'assets/icons/ic_card_pay.svg',
            onPressed: () => _confirm(context),
          ),
          // Ordernya sudah dibuat, tetapi pemesanannya masih
          // PENDING_PAYMENT — backend masih menerima pembatalan.
          const CancelTransactionButton(),
          SecondaryButton(
            label: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
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
                IconDetailRow(
                  asset: 'assets/icons/ic_charge_box.svg',
                  label: 'Charge Box',
                  value: '${chargeBox.badge} ${chargeBox.name}',
                ),
                const _Separator(),
                IconDetailRow(
                  asset: 'assets/icons/ic_connector.svg',
                  label: 'Konektor',
                  value: connector.name,
                ),
                const _Separator(),
                IconDetailRow(
                  asset: 'assets/icons/ic_nominal.svg',
                  label: 'Nominal',
                  value: formatKwh(order.kwh),
                ),
                const SizedBox(height: 12),
                // Blok rincian biaya berlatar #ECF5FE (73:2643).
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.breakdownBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      CostRows(price: order),
                      const SizedBox(height: 12),
                      TotalRow(amount: order.rpTotal, solid: true),
                    ],
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

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, thickness: 1, color: AppColors.borderAlt),
    );
  }
}
