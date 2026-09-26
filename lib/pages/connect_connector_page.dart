import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/charging_scope.dart';
import '../models/charging_session.dart';
import '../models/ocpp_status.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/expiry_ticker.dart';
import '../widgets/help_dialog.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'charging_started_page.dart';

/// Frame Figma 73:3470 "Hubungkan Konektor" dan 73:3597 "Konektor
/// Terhubung" — dua state dari layar yang sama.
///
/// Kabel yang tercolok dideteksi lewat `POST /check-status-connector`,
/// yang dipanggil tiap detik sampai status OCPP konektornya menjadi
/// "Preparing". Sebelum itu tombol "Mulai Pengisian" tetap mati:
/// perintah start yang dikirim sebelum kabel terpasang pasti ditolak
/// charger.
///
/// Status yang tidak dikenal tidak dianggap terpasang, dan "Faulted"
/// atau "Unavailable" dikatakan apa adanya — menunggu lebih lama tidak
/// akan mengubahnya.
///
/// Tanpa [ChargingScope] (mode offline) tidak ada yang bisa ditanya,
/// jadi tombolnya menyala setelah jeda [_simulationDelay].
class ConnectConnectorPage extends StatefulWidget {
  const ConnectConnectorPage({super.key, required this.session});

  final ChargingSession session;

  @override
  State<ConnectConnectorPage> createState() => _ConnectConnectorPageState();
}

class _ConnectConnectorPageState extends State<ConnectConnectorPage>
    with ExpiryTicker<ConnectConnectorPage> {
  static const _simulationDelay = Duration(seconds: 3);

  @override
  ChargingSession get expirySession => widget.session;

  Timer? _detection;
  bool _connected = false;
  bool _starting = false;

  /// Status OCPP terakhir yang dilaporkan charger, untuk ditampilkan
  /// bila konektornya sedang bermasalah.
  String _status = '';

  /// Satu pemeriksaan berjalan dalam satu waktu, supaya permintaan
  /// tidak menumpuk saat jaringan lambat.
  bool _checking = false;

  ChargingScope? _scope;

  @override
  void initState() {
    super.initState();

    startExpiryTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= ChargingScope.maybeOf(context);
    _detection ??= _scope == null
        ? Timer(_simulationDelay, _markPluggedIn)
        : Timer.periodic(Env.connectorPollInterval, (_) => _pollConnector());
  }

  /// Menanyakan status OCPP konektor dan menunggu kabelnya terpasang.
  ///
  /// Kegagalan diabaikan: pengguna masih memasang kabel, dan percobaan
  /// berikutnya menyusul sedetik kemudian.
  Future<void> _pollConnector() async {
    if (_checking || _connected || !mounted) return;
    _checking = true;

    try {
      final check = await _scope!.repository.checkConnectorStatus(
        chargeBoxId: widget.session.chargeBox.id,
        connectorId: widget.session.connector.id,
      );
      if (!mounted) return;

      debugPrint('[FLOW] Status konektor: ${check.status}');
      if (check.status != _status) setState(() => _status = check.status);
      if (check.isPluggedIn) _markPluggedIn();
    } on Object catch (_) {
      // Dicoba lagi pada pemeriksaan berikutnya.
    } finally {
      _checking = false;
    }
  }

  void _markPluggedIn() {
    if (!mounted || _connected) return;
    _detection?.cancel();
    debugPrint('[FLOW] Konektor terpasang — tombol "Mulai Pengisian" aktif');
    setState(() => _connected = true);
  }

  @override
  void dispose() {
    stopExpiryTicker();
    _detection?.cancel();
    super.dispose();
  }

  /// Meminta charger memulai sesi, lalu ke halaman "Pengisian Dimulai"
  /// yang menampilkan kode sesinya.
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
        // Charge box, konektor, dan kWh-nya sudah melekat pada order,
        // jadi cukup orderId.
        await scope.repository.startCharging(orderId: widget.session.orderId);
        // Controller hanya meneruskan perintah; konfirmasi pengisian
        // benar-benar jalan datang dari ongoing-kwh yang dipantau
        // halaman status.
        debugPrint('[FLOW] Perintah start terkirim');

        // Konektornya sekarang sedang dipakai, bukan sekadar dipesan —
        // kembalinya pengguna ke daftar tidak boleh melepasnya.
        // Ordernya tetap diingat supaya sesinya bisa dibuka lagi.
        scope.booking.startedCharging(orderId: widget.session.orderId);
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

    // Tahap ini lewat: tenggat yang habis tidak boleh lagi memulangkan
    // pengguna dari halaman di atas sini.
    stopExpiryTicker();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChargingStartedPage(session: widget.session),
      ),
    );
  }

  /// Apa yang sedang ditunggu, menurut charger sendiri.
  ///
  /// Charger yang rusak atau dimatikan tidak akan pernah melaporkan
  /// "Preparing"; mengatakan "Menunggu konektor terdeteksi…" di situ
  /// hanya membuat pengguna berdiri menunggu sesuatu yang tidak akan
  /// datang.
  String get _waitingLabel => OcppStatus.isBroken(_status)
      ? 'Konektor sedang tidak bisa dipakai ($_status). Hubungi petugas.'
      : 'Menunggu konektor terdeteksi...';

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: _connected ? 'Konektor Terhubung' : 'Hubungkan Konektor',
      subtitle: widget.session.breadcrumb,
      backgroundColor: AppColors.pageBackgroundPlain,
      headerExtra: CountdownPill(remaining: remaining),
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
            onPressed: () => showHelpDialog(context),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WaitingPanel(label: _waitingLabel),
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
