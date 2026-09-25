import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../data/final_energy.dart';
import '../data/formatters.dart';
import '../models/charging_session.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'charging_finished_page.dart';

/// Frame Figma 73:5075 — "Konfirmasi Akhiri Pengisian".
///
/// Mengembalikan `true` lewat Navigator bila sesi benar-benar diakhiri,
/// sehingga halaman status tahu harus berhenti menghitung.
class StopConfirmPage extends StatefulWidget {
  const StopConfirmPage({
    super.key,
    required this.session,
    required this.energyKwh,
  });

  final ChargingSession session;
  final double energyKwh;

  @override
  State<StopConfirmPage> createState() => _StopConfirmPageState();
}

class _StopConfirmPageState extends State<StopConfirmPage> {
  bool _stopping = false;

  ChargingSession get session => widget.session;
  double get energyKwh => widget.energyKwh;

  Future<void> _confirm() async {
    if (_stopping) return;
    final scope = ChargingScope.maybeOf(context);

    // Tanpa scope, atau tanpa orderId — sesi yang dilanjutkan dari
    // daftar charge box — tidak ada yang bisa dihentikan lewat backend.
    if (scope == null || session.orderId.isEmpty) {
      debugPrint(
        'Perintah stop DILEWATI: '
        '${scope == null ? 'tidak ada ChargingScope' : 'sesi tanpa orderId'}.',
      );
      _goToFinished(energyKwh);
      return;
    }

    setState(() => _stopping = true);
    try {
      await scope.repository.stopCharging(orderId: session.orderId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    final finalEnergy = await readFinalEnergy(
      repository: scope.repository,
      orderId: session.orderId,
      fallbackKwh: energyKwh,
    );
    if (!mounted) return;
    _goToFinished(finalEnergy);
  }

  void _goToFinished(double finalEnergyKwh) {
    // Sesinya sudah tamat; tidak ada lagi yang perlu diingat.
    ChargingScope.maybeOf(context)?.booking.forget();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ChargingFinishedPage(session: session, energyKwh: finalEnergyKwh),
        settings: const RouteSettings(name: 'pengisian-selesai'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Akhiri Pengisian?',
      titleAlign: TextAlign.center,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          DangerButton(
            label: _stopping ? 'Menghentikan…' : 'Ya, Akhiri Pengisian',
            onPressed: _stopping ? null : _confirm,
          ),
          SecondaryButton(
            label: 'Lanjut Pengisian',
            onPressed: _stopping
                ? null
                : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      child: Column(
        children: [
          const Expanded(
            child: AssetSlot(
              'assets/images/stop_confirm.png',
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Sesi yang dilanjutkan dari daftar tidak membawa data
                // pembelian, jadi kartunya disembunyikan daripada
                // menampilkan angka yang tidak diketahui.
                if (session.hasPurchase) ...[
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
                          label: 'Pembayaran Awal',
                          value: formatRupiah(session.paidAmount ?? 0),
                          muted: true,
                        ),
                        const SizedBox(height: 12),
                        DetailRow(
                          label: 'Pemakaian Sementara',
                          value: formatRupiah(
                            session.usageCostFor(energyKwh) ?? 0,
                          ),
                          muted: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const NoticeBar(
                  text: 'Nilai akhir dihitung setelah charger berhenti.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
