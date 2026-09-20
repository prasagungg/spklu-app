import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booking_progress.dart';
import '../data/charging_scope.dart';
import '../models/booking.dart';
import '../models/charging_session.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
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
/// BELUM ADA DETEKSI KONEKTOR SUNGGUHAN. Sebelumnya halaman ini
/// mem-polling `GET /list` sampai status konektor berubah menjadi
/// "Preparing" — tanda kabel tercolok ke kendaraan. `POST
/// /list-chargerbox` tidak membawa status OCPP itu, dan endpoint
/// pengecekan penggantinya belum tersedia.
///
/// Sampai endpoint itu ada, tombol "Mulai Pengisian" diaktifkan setelah
/// jeda [_simulationDelay] — perilaku yang selama ini hanya dipakai
/// mode offline. Alurnya tetap utuh, tetapi tidak ada jaminan kabel
/// benar-benar sudah terpasang; charger yang menolak `/start` akan
/// terlihat sebagai pesan error dari [startErrorMessage].
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

    _detection = Timer(_simulationDelay, _markPluggedIn);
  }

  void _markPluggedIn() {
    if (!mounted || _connected) return;
    _detection?.cancel();
    debugPrint(
      '[FLOW] Jeda deteksi habis — tombol "Mulai Pengisian" diaktifkan',
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

    reportBookingStage(
      context,
      chargeBoxId: widget.session.chargeBox.id,
      connectorId: widget.session.connector.id,
      stage: BookingStage.starting,
    );

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
          targetKwh: widget.session.price?.kwh,
        );
        // Controller hanya meneruskan perintah; konfirmasi pengisian
        // benar-benar jalan datang dari GET /progress yang dipantau
        // halaman status.
        debugPrint('Perintah start diterima: $result');

        // Konektornya sekarang sedang dipakai, bukan sekadar dipesan —
        // kembalinya pengguna ke daftar tidak boleh melepasnya.
        scope.booking.forget();
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
/// pengguna.
String startErrorMessage(ApiException e) => switch (e.responseCode) {
  ResponseCode.chargePointOffline =>
    'Charge box sedang tidak terhubung ke controller. '
        'Pilih charge box lain atau coba lagi sebentar.',
  ResponseCode.commandRejected =>
    'Charger menolak perintah. Pastikan konektor sudah terpasang '
        'dengan benar, lalu coba lagi.',
  ResponseCode.chargePointTimedOut =>
    'Charger tidak menjawab tepat waktu. Coba lagi sebentar.',
  ResponseCode.connectorRequired =>
    'Charger ini sedang melayani lebih dari satu sesi. Kembali dan '
        'pilih konektornya lagi.',
  ResponseCode.missingField =>
    'Data charge box tidak lengkap. Kembali dan pilih ulang.',
  _ => generalErrorMessage(e),
};
