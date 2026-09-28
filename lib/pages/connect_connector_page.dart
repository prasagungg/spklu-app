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
/// Halaman ini berjalan sendiri dari awal sampai akhir — tidak ada
/// tombol "Mulai Pengisian". Kabel yang sudah terpasang tidak menyisakan
/// keputusan apa pun untuk pengguna, dan tombol yang hanya punya satu
/// jawaban benar lebih baik ditekan aplikasi.
///
/// Kabel yang tercolok dideteksi lewat `POST /check-status-connector`,
/// yang dipanggil tiap detik sampai status OCPP konektornya menjadi
/// "Preparing". Status yang tidak dikenal tidak dianggap terpasang, dan
/// "Faulted" atau "Unavailable" dikatakan apa adanya — menunggu lebih
/// lama tidak akan mengubahnya.
///
/// **Hubungkan Konektor tidak pernah dilewati.** Perpindahan ke
/// "Konektor Terhubung" menunggu dua syarat sekaligus: kabelnya
/// terdeteksi, dan layar ini sudah tampil selama [waitingPause]. Satu
/// aturan itu menutupi ketiga keadaannya:
///
/// | Keadaan | Yang menahan | Yang dilihat |
/// |---|---|---|
/// | Belum tercolok | deteksinya | loading terus sampai kabelnya masuk |
/// | Tercolok sambil menunggu | yang belakangan selesai | seperti di atas, lalu pindah |
/// | Sudah tercolok sejak halaman dibuka | jedanya | Hubungkan Konektor 2–4 detik, baru pindah |
///
/// Tanpa jeda itu, kabel yang sudah terpasang membuat layarnya
/// berkelebat, dan yang tersisa di ingatan pengguna hanyalah aplikasi
/// yang melompat sendiri tanpa penjelasan.
///
/// Sesudah pindah, "Konektor Terhubung" menahan diri [waitingPause]
/// sekali lagi sebelum `/start` berangkat — bukan supaya charger siap,
/// charger tidak peduli kapan perintahnya datang, melainkan supaya
/// pengguna sempat membaca bahwa konektornya memang sudah terdeteksi.
///
/// Tanpa [ChargingScope] (mode offline) tidak ada yang bisa ditanya,
/// jadi kabelnya dianggap terpasang setelah [_simulationDelay].
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
  bool _starting = false;

  /// Charger melaporkan kabelnya sudah terpasang. Menghentikan
  /// pemeriksaan, tapi belum tentu memindahkan layar — lihat
  /// [_connected].
  bool _pluggedIn = false;

  /// Layar "Hubungkan Konektor" sudah tampil cukup lama untuk dibaca.
  bool _introDone = false;

  /// Layarnya menampilkan "Konektor Terhubung".
  ///
  /// Dua syarat, bukan satu: kabel yang sudah terpasang sejak halaman
  /// dibuka tetap harus melewati layar Hubungkan Konektor, kalau tidak
  /// layar itu cuma berkelebat selama satu round trip.
  bool get _connected => _pluggedIn && _introDone;

  /// Jeda tampil minimum layar "Hubungkan Konektor".
  Timer? _intro;

  /// Jeda "Konektor Terhubung" sebelum `/start` dikirim.
  Timer? _autoStart;

  /// Kegagalan `/start` terakhir. Tanpa tombol alur normal, inilah
  /// satu-satunya jalan keluar dari layar tunggu ketika charger menolak.
  String _startError = '';

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

    _intro = Timer(waitingPause(), () {
      _introDone = true;
      _advanceIfReady();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= ChargingScope.maybeOf(context);
    if (_detection != null) return;

    if (_scope == null) {
      _detection = Timer(_simulationDelay, _markPluggedIn);
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
    if (_checking || _pluggedIn || !mounted) return;
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
    if (!mounted || _pluggedIn) return;
    _detection?.cancel();
    debugPrint('[FLOW] Konektor terpasang');
    _pluggedIn = true;
    _advanceIfReady();
  }

  /// Menampilkan "Konektor Terhubung" begitu kedua syaratnya terpenuhi,
  /// lalu menjadwalkan `/start`.
  ///
  /// Dipanggil dari dua arah — deteksi dan jeda tampil — dan yang
  /// belakangan datanglah yang benar-benar memindahkan layar.
  void _advanceIfReady() {
    if (!mounted || !_connected || _autoStart != null) return;

    setState(() {});
    _autoStart = Timer(waitingPause(), _start);
  }

  @override
  void dispose() {
    stopExpiryTicker();
    _detection?.cancel();
    // Tombol Home yang ditekan di tengah jeda tidak boleh mengirim
    // /start untuk halaman yang sudah mati.
    _intro?.cancel();
    _autoStart?.cancel();
    super.dispose();
  }

  /// Menjadwalkan ulang `/start` setelah kegagalan, atas permintaan
  /// pengguna.
  void _retry() {
    setState(() => _startError = '');
    _autoStart = Timer(waitingPause(), _start);
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
    _autoStart = null;

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
        // Halaman ini tidak punya tombol alur normal, jadi kegagalannya
        // harus memunculkan jalan keluarnya sendiri. Tanpa itu pengguna
        // tertahan di layar tunggu yang tidak akan pernah selesai.
        //
        // Tidak dicoba ulang sendiri: charger yang menolak sekali
        // biasanya menolak lagi, dan mengulanginya tiap beberapa detik
        // hanya menghujani perangkat yang sedang bermasalah.
        setState(() {
          _starting = false;
          _startError = startErrorMessage(e);
        });
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

  /// Bilah tombol halaman ini, yang sebagian besar waktu tidak ada.
  ///
  /// Alur normalnya tidak menunggu apa pun dari pengguna. Yang tersisa
  /// dua keadaan yang benar-benar memerlukan tangannya: memasang kabel,
  /// saat bantuan paling mungkin dibutuhkan, dan `/start` yang ditolak
  /// charger, yang tanpa tombol tidak punya jalan keluar sama sekali.
  Widget? _bottomBar(BuildContext context) {
    if (_startError.isNotEmpty) {
      return BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: 'Coba Lagi',
            trailingAsset: 'assets/icons/ic_play.svg',
            onPressed: _retry,
          ),
          SecondaryButton(
            label: 'Bantuan',
            trailingAsset: 'assets/icons/ic_support.svg',
            onPressed: () => showHelpDialog(context),
          ),
        ],
      );
    }

    if (_connected) return null;

    return BottomActionBar(
      opaque: false,
      children: [
        SecondaryButton(
          label: 'Bantuan',
          trailingAsset: 'assets/icons/ic_support.svg',
          onPressed: () => showHelpDialog(context),
        ),
      ],
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
      bottomBar: _bottomBar(context),
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
          if (_startError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HintStrip(text: _startError),
            )
          else if (_connected) ...[
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
              const _ConnectedPanel(),
            // Tanpa bilah tombol, isi halaman sendiri yang memberi jarak
            // ke tepi bawah.
            const SizedBox(height: 24),
          ] else ...[
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
              'Pengisian akan dimulai otomatis.',
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
