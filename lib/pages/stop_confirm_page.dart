import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
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
  /// Charger masih menyalurkan daya beberapa saat setelah perintah
  /// stop, jadi angka akhirnya ditunggu sampai `/progress` melaporkan
  /// "finished" — bukan diambil dari nilai saat tombol ditekan.
  static const _finalReadAttempts = 5;
  static const _finalReadDelay = Duration(seconds: 1);

  bool _stopping = false;

  ChargingSession get session => widget.session;
  double get energyKwh => widget.energyKwh;

  Future<void> _confirm() async {
    if (_stopping) return;
    final scope = ChargingScope.maybeOf(context);

    if (scope == null) {
      debugPrint(
        'ChargingScope tidak ditemukan — /stop DILEWATI dan alur '
        'berjalan offline.',
      );
      _goToFinished(energyKwh);
      return;
    }

    setState(() => _stopping = true);
    try {
      await scope.repository.stopCharging(
        chargePointId: session.chargeBox.id,
        connectorId: session.connector.id,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    }

    final finalEnergy = await _readFinalEnergy(scope);
    if (!mounted) return;
    _goToFinished(finalEnergy);
  }

  /// Membaca `/progress` sampai sesi benar-benar berhenti, lalu memakai
  /// angka energinya.
  ///
  /// Kalau sampai batas percobaan belum juga "finished", dipakai
  /// bacaan terakhir yang berhasil — tetap lebih akurat daripada nilai
  /// saat tombol ditekan. Kegagalan total jatuh ke nilai itu.
  Future<double> _readFinalEnergy(ChargingScope scope) async {
    var latest = energyKwh;

    for (var attempt = 0; attempt < _finalReadAttempts; attempt++) {
      await Future<void>.delayed(_finalReadDelay);
      if (!mounted) return latest;

      try {
        final progress = await scope.repository.fetchProgress(
          chargePointId: session.chargeBox.id,
          connectorId: session.connector.id,
        );
        if (progress == null) continue;

        latest = progress.energyKwh;
        debugPrint(
          '[FLOW] Bacaan akhir ${attempt + 1}: state=${progress.state} '
          'energi=${progress.energyKwh} kWh',
        );
        if (progress.isFinished) return latest;
      } on Object catch (_) {
        // Dicoba lagi; kalau habis, pakai bacaan terakhir.
      }
    }

    return latest;
  }

  void _goToFinished(double finalEnergyKwh) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<bool>(
        builder: (_) => ChargingFinishedPage(
          session: session,
          energyKwh: finalEnergyKwh,
        ),
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
            onPressed:
                _stopping ? null : () => Navigator.of(context).pop(false),
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
                          value: formatRupiah(session.nominal!.amount),
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
