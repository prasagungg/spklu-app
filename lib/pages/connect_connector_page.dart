import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../models/charging_session.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'card_payment_page.dart';
import 'charging_status_page.dart';

/// Frame Figma 73:3470 "Hubungkan Konektor" dan 73:3597 "Konektor
/// Terhubung" — dua state dari layar yang sama.
///
/// Deteksi konektor nyata: halaman ini mem-polling `GET /list` sampai
/// status konektor yang dipilih berubah dari "Available" menjadi
/// "Preparing" — tanda kabel sudah tercolok ke kendaraan. Baru setelah
/// itu `/start` boleh dikirim.
///
/// Tanpa [ChargingScope] (mode offline untuk test), deteksi itu
/// disimulasikan dengan jeda [_simulationDelay].
class ConnectConnectorPage extends StatefulWidget {
  const ConnectConnectorPage({super.key, required this.session});

  final ChargingSession session;

  @override
  State<ConnectConnectorPage> createState() => _ConnectConnectorPageState();
}

class _ConnectConnectorPageState extends State<ConnectConnectorPage> {
  static const _limit = Duration(minutes: 10);
  static const _simulationDelay = Duration(seconds: 3);

  Timer? _ticker;
  Timer? _detection;
  Duration _remaining = _limit;
  bool _connected = false;
  bool _starting = false;
  bool _checking = false;

  ChargingScope? _scope;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= ChargingScope.maybeOf(context);
    _detection ??= _scope == null
        ? Timer(_simulationDelay, _markPluggedIn)
        : Timer.periodic(Env.connectorPollInterval, (_) => _pollConnector());
  }

  /// Membaca `/list` dan menunggu konektor yang dipilih meninggalkan
  /// status "Available".
  ///
  /// Kegagalan polling diabaikan: pengguna masih memasang kabel, dan
  /// percobaan berikutnya menyusul dua detik kemudian.
  Future<void> _pollConnector() async {
    if (_checking || _connected || !mounted) return;
    _checking = true;
    try {
      final box = await _scope!.repository.fetchChargeBox(
        widget.session.chargeBox.id,
      );
      if (box == null || !mounted) return;

      for (final connector in box.connectors) {
        if (connector.id != widget.session.connector.id) continue;
        debugPrint(
          '[FLOW] Status konektor ${connector.id}: ${connector.rawStatus}',
        );
        if (connector.isPluggedIn) _markPluggedIn();
        break;
      }
    } on Object catch (_) {
      // Dicoba lagi pada polling berikutnya.
    } finally {
      _checking = false;
    }
  }

  void _markPluggedIn() {
    if (!mounted || _connected) return;
    _detection?.cancel();
    debugPrint(
      '[FLOW] Konektor terpasang — tombol "Mulai Pengisian" aktif',
    );
    setState(() => _connected = true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _detection?.cancel();
    super.dispose();
  }

  /// Meminta charger memulai sesi, lalu langsung ke layar status.
  /// Interstitial "Pengisian Dimulai" (73:3667) dilewati agar start,
  /// stop, dan pemantauan berada dalam satu alur.
  Future<void> _start() async {
    debugPrint(
      '[FLOW] "Mulai Pengisian" ditekan di Konektor Terhubung — '
      'charge box ${widget.session.chargeBox.id}, '
      'konektor ${widget.session.connector.id}',
    );

    if (_starting) return;
    final scope = ChargingScope.maybeOf(context);

    if (scope == null) {
      debugPrint(
        'ChargingScope tidak ditemukan — /start DILEWATI dan alur '
        'berjalan offline. Di aplikasi sungguhan ini berarti scope-nya '
        'tidak terpasang di atas MaterialApp.',
      );
    }

    if (scope != null) {
      setState(() => _starting = true);
      try {
        final result = await scope.repository.startCharging(
          chargePointId: widget.session.chargeBox.id,
          connectorId: widget.session.connector.id,
          // kWh yang dibeli pengguna pada halaman Pilih Nominal.
          targetKwh: widget.session.nominal?.kwh,
        );
        // Controller hanya meneruskan perintah; konfirmasi pengisian
        // benar-benar jalan datang dari `session` pada GET /list yang
        // dipantau halaman status.
        debugPrint('Perintah start diterima: $result');
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _starting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(startErrorMessage(e))));
        return;
      }
      if (!mounted) return;
    }

    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChargingStatusPage(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: _connected ? 'Konektor Terhubung' : 'Hubungkan Konektor',
      subtitle: widget.session.breadcrumb,
      backgroundColor: AppColors.pageBackgroundPlain,
      headerExtra: CountdownPill(remaining: _remaining),
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: _starting ? 'Memulai…' : 'Mulai Pengisian',
            trailingAsset: 'assets/icons/ic_play.svg',
            // Nonaktif sampai konektor terdeteksi (73:3530), dan selama
            // permintaan /start masih berjalan.
            onPressed: _connected && !_starting ? _start : null,
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
          Expanded(
            child: AssetSlot(
              _connected
                  ? 'assets/images/connector_connected.png'
                  : 'assets/images/connector_plug.png',
              fit: BoxFit.contain,
            ),
          ),
          if (_connected)
            const _ConnectedPanel()
          else ...[
            const HintStrip(text: 'Pasang konektor ke kendaraan Anda.'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: WaitingPanel(label: 'Menunggu konektor terdeteksi...'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Panel konfirmasi dengan lencana centang yang menggantung di atasnya
/// (73:3632).
class _ConnectedPanel extends StatelessWidget {
  const _ConnectedPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Sisi atas diberi ruang untuk lencana yang menonjol keluar.
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          const GlassPanel(
            padding: EdgeInsets.all(16),
            child: Text(
              'Konektor berhasil terdeteksi,\n'
              'Silakan memulai pengisian sekarang.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.title,
              ),
            ),
          ),
          const Positioned(
            top: -18,
            child: AssetSlot(
              'assets/icons/ic_check_badge.svg',
              width: 36,
              height: 36,
            ),
          ),
        ],
      ),
    );
  }
}

/// Menerjemahkan kegagalan `/start` jadi arahan yang bisa ditindaklanjuti
/// pengguna. Kode yang tidak dikenal memakai pesan asli dari backend.
String startErrorMessage(ApiException e) => switch (e.responseCode) {
  ChargeErrorCode.notConnected =>
    'Charge box sedang tidak terhubung ke controller. '
        'Pilih charge box lain atau coba lagi sebentar.',
  ChargeErrorCode.rejected =>
    'Charger menolak perintah. Pastikan konektor sudah terpasang '
        'dengan benar, lalu coba lagi.',
  ChargeErrorCode.missingField =>
    'Data charge box tidak lengkap. Kembali dan pilih ulang.',
  _ => e.message,
};
