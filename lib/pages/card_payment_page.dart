import 'dart:async';

import 'package:flutter/material.dart';

import '../data/formatters.dart';
import '../models/charging_session.dart';
import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'payment_success_page.dart';

/// Frame Figma 73:2776 — "Pembayaran Kartu".
///
/// Tap kartu e-Money tidak disimulasikan lewat NFC; tampilannya statis
/// dan ada tombol "Bayar (Simulasi)" untuk memajukan alur demo.
class CardPaymentPage extends StatefulWidget {
  const CardPaymentPage({super.key, required this.session});

  final ChargingSession session;

  @override
  State<CardPaymentPage> createState() => _CardPaymentPageState();
}

class _CardPaymentPageState extends State<CardPaymentPage> {
  static const _limit = Duration(minutes: 10);

  Timer? _ticker;
  Duration _remaining = _limit;

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

  void _pay() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PaymentSuccessPage(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pembayaran',
      subtitle: 'Tempelkan kartu e-Money Anda pada reader.',
      backgroundColor: AppColors.pageBackgroundPlain,
      // Halaman ini memakai ilustrasi reader sebagai latar penuh.
      backgroundAsset: 'assets/images/bg_payment.png',
      backgroundOpacity: 1,
      headerExtra: CountdownPill(remaining: _remaining),
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          // Tambahan di luar desain: pemicu untuk demo, karena tap
          // kartu yang sebenarnya perlu perangkat NFC.
          PrimaryButton(
            label: 'Bayar (Simulasi)',
            trailingAsset: 'assets/icons/ic_card_pay.svg',
            onPressed: _pay,
          ),
          SecondaryButton(
            label: 'Bantuan',
            trailingAsset: 'assets/icons/ic_support.svg',
            onPressed: () => showHelpSheet(context),
          ),
        ],
      ),
      child: Column(
        children: [
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: WaitingPanel(label: 'Menunggu Kartu', soft: true),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SessionInfoRow(
              // Halaman pembayaran hanya dicapai dari alur pembelian.
              nominalLabel: formatRupiah(widget.session.nominal!.amount),
              sessionCode: widget.session.sessionCode,
            ),
          ),
        ],
      ),
    );
  }
}

/// Frame Figma 73:2935 — "Bantuan", ditampilkan sebagai bottom sheet.
Future<void> showHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Butuh Bantuan?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.title,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hubungi petugas di lokasi atau call center PLN 123 bila '
              'pengisian tidak berjalan sebagaimana mestinya.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.description,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Tutup',
                trailingAsset: null,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
