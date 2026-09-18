import 'dart:async';

import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../config/env.dart';
import '../models/charging_session.dart';
import '../models/session_info.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import 'charging_finished_page.dart';
import 'stop_confirm_page.dart';

/// Frame Figma 73:4979 — "Sedang Mengisi".
///
/// Layar status pengisian: menampilkan energi yang sudah tersalur dan
/// menyediakan tombol untuk menghentikan sesi.
///
/// Energi dibaca dengan mem-polling `GET /progress` tiap detik. Ketika
/// `state` berubah menjadi "finished" — entah karena pengguna menekan
/// Akhiri Pengisian atau charger berhenti sendiri — halaman langsung
/// berpindah ke rincian akhir.
///
/// Tanpa [ChargingScope] halaman jatuh ke simulasi lokal.
class ChargingStatusPage extends StatefulWidget {
  const ChargingStatusPage({super.key, required this.session});

  final ChargingSession session;

  @override
  State<ChargingStatusPage> createState() => _ChargingStatusPageState();
}

class _ChargingStatusPageState extends State<ChargingStatusPage> {
  /// Kenaikan energi per detik pada simulasi offline.
  static const double _kwhPerTick = 0.4;

  Timer? _ticker;
  bool _polling = false;

  /// Bacaan terakhir dari `GET /progress` — sumber tunggal angka yang
  /// ditampilkan saat daring.
  SessionInfo? _progress;

  /// Hanya dipakai saat tidak ada [ChargingScope].
  double _simulatedKwh = 0;

  ChargingScope? _scope;

  /// Energi tersalur. Selalu angka dari `/progress` bila ada; simulasi
  /// hanya menambal mode offline.
  double get _energyKwh => _progress?.energyKwh ?? _simulatedKwh;

  @override
  void initState() {
    super.initState();
    // Saat halaman ini dibuka dari konektor yang sudah mengisi, `/list`
    // sudah membawa sesinya. Dipakai sebagai nilai awal supaya layar
    // tidak sempat menampilkan 0 kWh sebelum polling pertama selesai.
    _progress = widget.session.connector.session;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= ChargingScope.maybeOf(context);
    _ticker ??= _startTicker();
  }

  Timer _startTicker() {
    final live = _scope != null;
    return Timer.periodic(
      live ? Env.progressPollInterval : const Duration(seconds: 1),
      (_) => live ? _poll() : _tick(),
    );
  }

  /// Mode offline: energi dinaikkan tetap tiap detik.
  void _tick() {
    if (!mounted) return;
    // Tanpa data pembelian, simulasi offline dibatasi nilai wajar.
    final max = widget.session.nominal?.kwh ?? 20;
    if (_simulatedKwh >= max) {
      _ticker?.cancel();
      return;
    }
    setState(() {
      _simulatedKwh = (_simulatedKwh + _kwhPerTick).clamp(0, max).toDouble();
    });
  }

  /// Mode daring: baca kemajuan sesi lewat `GET /progress`.
  ///
  /// Kegagalan polling sengaja tidak memunculkan error — sesi tetap
  /// berjalan di charger, dan angka terakhir dibiarkan apa adanya
  /// sampai polling berikutnya berhasil.
  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final progress = await _scope!.repository.fetchProgress(
        chargePointId: widget.session.chargeBox.id,
        connectorId: widget.session.connector.id,
      );
      if (!mounted || progress == null) return;

      setState(() => _progress = progress);

      if (progress.isFinished) {
        debugPrint(
          '[FLOW] Sesi selesai di charger '
          '(state=${progress.state} alasan=${progress.stopReason}) — '
          'menuju rincian akhir',
        );
        _finish(progress.energyKwh);
      }
    } on Object catch (_) {
      // Diabaikan; dicoba lagi pada polling berikutnya.
    } finally {
      _polling = false;
    }
  }

  /// Sesi berakhir di sisi charger, bukan lewat tombol di aplikasi.
  void _finish(double energyKwh) {
    _ticker?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChargingFinishedPage(
          session: widget.session,
          energyKwh: energyKwh,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _stop() async {
    _ticker?.cancel();

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StopConfirmPage(
          session: widget.session,
          energyKwh: _energyKwh,
        ),
      ),
    );

    if (!mounted) return;

    // Batal menghentikan — pemantauan dijalankan kembali.
    if (confirmed != true) {
      _ticker = _startTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Sedang Mengisi',
      titleAlign: TextAlign.center,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          DangerOutlineButton(label: 'Akhiri Pengisian', onPressed: _stop),
          SecondaryButton(
            label: 'Kembali ke Halaman Awal',
            trailingAsset: 'assets/icons/ic_home_filled.svg',
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      child: Column(
        children: [
          const Expanded(
            child: AssetSlot(
              'assets/images/battery_charging.png',
              fit: BoxFit.contain,
            ),
          ),
          Text(
            // Desimalnya menyesuaikan supaya angkanya tidak terlihat
            // mandek di "0,0 kWh" saat pengisian baru mulai.
            formatEnergy(_energyKwh),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Energi tersalur',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.description,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
