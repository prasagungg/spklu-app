import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/charging_scope.dart';
import '../data/waiting_pause.dart';
import '../models/charging_session.dart';
import '../models/ocpp_status.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/expiry_ticker.dart';
import '../widgets/help_dialog.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/session_expired_dialog.dart';
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
/// Bila pemeriksaan **pertama** sudah melaporkan kabelnya terpasang,
/// pengguna memasangnya sebelum halaman ini dibuka dan tidak ada yang
/// perlu ditunggu darinya: halaman berjalan sendiri — tombolnya tidak
/// ditampilkan dan perintah start dikirim tanpa ditekan. Kabel yang
/// dicolokkan *sambil* menunggu di halaman ini tetap mendapat alur
/// biasa, karena keputusannya diambil sekali di pemeriksaan pertama
/// saja.
///
/// Perintahnya tidak berangkat seketika: halaman menahan diri selama
/// [waitingPause] sambil mengatakan konektornya sudah terdeteksi.
/// Tanpa jeda itu layarnya cuma berkelebat, dan yang tersisa di ingatan
/// pengguna hanyalah aplikasi yang melompat sendiri tanpa penjelasan.
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

  /// Tahap ini hanya dicapai setelah pembayaran berhasil, jadi tenggat
  /// yang habis di sini berarti uang sudah terdebit tanpa pengisian.
  /// Rinciannya ditunjukkan dulu, baru pengguna dipulangkan.
  @override
  Future<void> handleExpiry() async {
    await showSessionExpiredDialog(context, session: widget.session);
    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Timer? _detection;
  bool _connected = false;
  bool _starting = false;

  /// Halaman ini menjalankan sendiri perintah start, tanpa tombol.
  /// Menyala hanya bila pemeriksaan pertama sudah menemukan kabelnya
  /// terpasang.
  bool _auto = false;

  /// Belum ada pemeriksaan yang benar-benar berangkat. Yang pertama
  /// berangkatlah yang berhak memutuskan mode otomatis.
  bool _firstCheckPending = true;

  /// Jeda mode otomatis sebelum `/start` dikirim.
  Timer? _autoStart;

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
    if (_detection != null) return;

    if (_scope == null) {
      _detection = Timer(_simulationDelay, () => _markPluggedIn());
      return;
    }

    _detection = Timer.periodic(
      Env.connectorPollInterval,
      (_) => _pollConnector(),
    );

    // Pemeriksaan pertama tidak menunggu satu putaran timer. Hasilnyalah
    // yang memutuskan halaman ini berjalan sendiri atau menunggu
    // pengguna, dan menundanya sedetik membuat layar sempat menyuruh
    // memasang kabel yang sudah terpasang.
    _pollConnector();
  }

  /// Menanyakan status OCPP konektor dan menunggu kabelnya terpasang.
  ///
  /// Kegagalan diabaikan: pengguna masih memasang kabel, dan percobaan
  /// berikutnya menyusul sedetik kemudian.
  Future<void> _pollConnector() async {
    if (_checking || _connected || !mounted) return;
    _checking = true;

    // Hanya pemeriksaan yang benar-benar berangkat yang menghabiskan
    // "pemeriksaan pertama". Putaran timer yang bertabrakan dengan
    // permintaan yang sedang berjalan sudah pulang di baris atas.
    final isFirstCheck = _firstCheckPending;
    _firstCheckPending = false;

    try {
      final check = await _scope!.repository.checkConnectorStatus(
        chargeBoxId: widget.session.chargeBox.id,
        connectorId: widget.session.connector.id,
      );
      if (!mounted) return;

      debugPrint('[FLOW] Status konektor: ${check.status}');
      if (check.status != _status) setState(() => _status = check.status);
      if (check.isPluggedIn) _markPluggedIn(auto: isFirstCheck);
    } on Object catch (_) {
      // Dicoba lagi pada pemeriksaan berikutnya.
    } finally {
      _checking = false;
    }
  }

  /// [auto] berarti kabelnya sudah terpasang sebelum halaman ini
  /// dibuka. Tidak ada yang perlu ditunggu dari pengguna, jadi perintah
  /// start dikirim di tempat dan tombolnya tidak ditampilkan.
  void _markPluggedIn({bool auto = false}) {
    if (!mounted || _connected) return;
    _detection?.cancel();
    debugPrint(
      auto
          ? '[FLOW] Konektor sudah terpasang saat halaman dibuka — '
                '/start dikirim tanpa menunggu tombol'
          : '[FLOW] Konektor terpasang — tombol "Mulai Pengisian" aktif',
    );
    setState(() {
      _connected = true;
      _auto = auto;
    });

    if (!auto) return;

    // Ditahan sebentar supaya pengguna sempat membaca bahwa konektornya
    // memang sudah terdeteksi, bukan supaya charger siap — charger tidak
    // peduli kapan perintahnya datang.
    _autoStart = Timer(waitingPause(), _start);
  }

  @override
  void dispose() {
    stopExpiryTicker();
    _detection?.cancel();
    // Tombol Home yang ditekan di tengah jeda tidak boleh mengirim
    // /start untuk halaman yang sudah mati.
    _autoStart?.cancel();
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
        // Mode otomatis tidak punya tombol, jadi kegagalannya harus
        // mengembalikan halaman ini ke mode biasa. Tanpa itu pengguna
        // tertahan di layar tunggu yang tidak akan pernah selesai.
        setState(() {
          _starting = false;
          _auto = false;
        });
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
      // Mode otomatis tidak menunggu apa pun dari pengguna, jadi tidak
      // ada yang perlu ditekan — termasuk Bantuan, yang di sini hanya
      // menawarkan pertolongan untuk masalah yang tidak ada.
      bottomBar: _auto
          ? null
          : BottomActionBar(
              opaque: false,
              children: [
                PrimaryButton(
                  label: _starting ? 'Memulai…' : 'Mulai Pengisian',
                  trailingAsset: 'assets/icons/ic_play.svg',
                  // Nonaktif sampai konektor terdeteksi (73:3530), dan
                  // selama permintaan /start masih berjalan.
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
          if (_auto) ...[
            // Dua fase: selama jeda, kabarnya dulu — inilah yang perlu
            // dibaca pengguna. Setelah perintahnya terbang, labelnya
            // sengaja beda dari "Menyiapkan pengisian…" di halaman
            // berikutnya, supaya dua layar tunggu berurutan tidak
            // terasa seperti satu layar yang mandek.
            if (_starting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: WaitingPanel(label: 'Memulai pengisian…'),
              )
            else
              const _ConnectedPanel(
                message:
                    'Konektor berhasil terdeteksi,\n'
                    'Pengisian akan dimulai otomatis.',
              ),
            // Tanpa bilah tombol, isi halaman sendiri yang memberi jarak
            // ke tepi bawah.
            const SizedBox(height: 24),
          ] else if (_connected)
            const _ConnectedPanel(
              message:
                  'Konektor berhasil terdeteksi,\n'
                  'Silakan memulai pengisian sekarang.',
            )
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
  const _ConnectedPanel({required this.message});

  /// Berbeda antara alur biasa dan mode otomatis: yang satu menyuruh
  /// menekan tombol, yang lain memberi tahu tidak ada yang perlu
  /// ditekan.
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Sisi atas diberi ruang untuk lencana yang menonjol keluar.
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
