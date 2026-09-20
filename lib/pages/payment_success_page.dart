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
import 'connect_connector_page.dart';

/// Frame Figma 73:3139 — "Pembayaran Sukses".
class PaymentSuccessPage extends StatefulWidget {
  const PaymentSuccessPage({super.key, required this.session});

  final ChargingSession session;

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage> {
  bool _detailExpanded = true;

  void _start() {
    // Tombol ini hanya berpindah ke layar pemasangan konektor.
    // Perintah /start baru dikirim dari layar berikutnya, setelah
    // konektor terdeteksi.
    debugPrint(
      '[FLOW] "Mulai Pengisian" ditekan di Pembayaran Berhasil — '
      'pindah ke Hubungkan Konektor, /start BELUM dikirim',
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConnectConnectorPage(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    // Halaman ini hanya dicapai lewat alur pembelian, jadi harganya
    // dipastikan ada.
    final price = session.price!;

    return PageScaffold(
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        children: [
          PrimaryButton(
            label: 'Mulai Pengisian',
            trailingAsset: 'assets/icons/ic_play.svg',
            onPressed: _start,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Center(
            child: AssetSlot(
              'assets/images/success_check.png',
              width: 180,
              height: 120,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pembayaran Berhasil',
            textAlign: TextAlign.center,
            style: AppTheme.pageTitle,
          ),
          const SizedBox(height: 4),
          const Text(
            'Silakan mulai pengisian dengan menekan tombol di bawah.',
            textAlign: TextAlign.center,
            style: AppTheme.pageSubtitle,
          ),
          const SizedBox(height: 16),
          SessionInfoRow(
            nominalLabel: formatRupiah(price.rpTotal),
            sessionCode: session.sessionCode,
          ),
          const SizedBox(height: 16),
          _TransactionDetail(
            session: session,
            expanded: _detailExpanded,
            onToggle: () => setState(() => _detailExpanded = !_detailExpanded),
          ),
        ],
      ),
    );
  }
}

/// Kartu "Detail Transaksi" (73:3229) yang bisa dilipat.
class _TransactionDetail extends StatelessWidget {
  const _TransactionDetail({
    required this.session,
    required this.expanded,
    required this.onToggle,
  });

  final ChargingSession session;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                const Expanded(
                  child: Text('Detail Transaksi', style: AppTheme.cardTitle),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const AssetSlot(
                    'assets/icons/ic_chevron_down.svg',
                    width: 20,
                    height: 20,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                const SizedBox(height: 12),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderAlt,
                ),
                const SizedBox(height: 12),
                DetailRow(
                  label: 'Jenis Layanan',
                  value: session.jenisLayanan,
                  muted: true,
                ),
                const SizedBox(height: 12),
                DetailRow(
                  label: 'No Reference',
                  value: session.reference,
                  muted: true,
                ),
                const SizedBox(height: 12),
                DetailRow(
                  label: 'Tanggal Transaksi',
                  value: session.formattedDate,
                  muted: true,
                ),
                const SizedBox(height: 12),
                CostRows(price: session.price!),
                const SizedBox(height: 12),
                TotalRow(amount: session.price!.rpTotal),
              ],
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}
