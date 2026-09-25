import 'dart:async';

import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../data/final_energy.dart';
import '../data/formatters.dart';
import '../config/env.dart';
import '../models/charging_session.dart';
import '../models/charging_progress.dart';
import '../models/session_check.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
import '../theme/app_colors.dart';
import '../widgets/battery_gauge.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'charging_finished_page.dart';
import 'session_verification_page.dart';

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

  /// Perintah stop sedang berjalan — tombolnya dimatikan supaya tidak
  /// terkirim dua kali.
  bool _stopping = false;

  /// Pengguna sedang mengakhiri sesi: layar verifikasi terbuka, atau
  /// perintah stop sedang diproses.
  ///
  /// Polling yang **sudah terbang** sebelum tombol ditekan tetap akan
  /// menjawab, dan jawabannya bisa berbunyi "selesai". Tanpa penanda
  /// ini, jawaban itu mendorong halaman rincian akhir dari balik layar
  /// verifikasi — halaman verifikasinya tergusur, lalu jalur stop
  /// mendorong rincian akhir sekali lagi. Itulah "Pengisian Selesai
  /// yang muncul dua kali dan tombolnya tidak bisa ditekan".
  bool _ending = false;

  /// Halaman rincian akhir sudah dibuka. Navigasi hanya boleh sekali.
  bool _finished = false;

  /// Bacaan terakhir dari `ongoing-kwh` — sumber tunggal angka yang
  /// ditampilkan saat daring.
  ChargingProgress? _progress;

  /// Hanya dipakai saat tidak ada [ChargingScope].
  double _simulatedKwh = 0;

  ChargingScope? _scope;

  /// Bisa menanyakan kemajuan ke backend.
  ///
  /// Sesi yang dilanjutkan dari daftar charge box tidak membawa
  /// orderId — semua endpoint pengisian berkunci order, jadi sesi itu
  /// hanya bisa disimulasikan lokal sampai ada cara memulihkan ordernya
  /// dari konektor.
  bool get _live => _scope != null && widget.session.orderId.isNotEmpty;

  /// Energi tersalur. Selalu angka dari `/progress` bila ada; simulasi
  /// hanya menambal mode offline.
  double get _energyKwh => _progress?.charged ?? _simulatedKwh;

  /// kWh yang dipesan — pembagi kemajuan pengisian.
  ///
  /// `orderKwh` dari `ongoing-kwh` yang berwenang; sesi yang dibuka dari
  /// unit ini punya cadangan dari ordernya sendiri.
  double get _orderedKwh {
    final ordered = _progress?.orderKwh ?? 0;
    if (ordered > 0) return ordered;

    return widget.session.price?.kwh ?? 0;
  }

  /// Seberapa penuh baterainya: energi tersalur dibagi kWh yang
  /// dipesan. 1 kWh dari 10 kWh berarti 0.1.
  ///
  /// Nol selama kWh pesanan belum diketahui — lebih baik tabung kosong
  /// daripada tinggi cairan yang mengarang.
  double get _fillRatio {
    final ordered = _orderedKwh;
    if (ordered <= 0) return 0;

    return (_energyKwh / ordered).clamp(0.0, 1.0);
  }

  // Nilai awal sengaja kosong: `POST /list-chargerbox` tidak membawa
  // sesi yang sedang berjalan, jadi angka pertama baru datang dari
  // polling `/progress`.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope ??= ChargingScope.maybeOf(context);
    _ticker ??= _startTicker();
  }

  Timer _startTicker() {
    final live = _live;

    // Bacaan pertama diminta sekarang juga, bukan menunggu detak
    // pertama: menunggu berarti layar sempat menampilkan "0 kWh" yang
    // bukan angka dari charger.
    if (live) unawaited(_poll());

    return Timer.periodic(
      live ? Env.progressPollInterval : const Duration(seconds: 1),
      (_) => live ? _poll() : _tick(),
    );
  }

  /// Bacaan pertama dari backend belum datang.
  ///
  /// Selama itu angka energi tidak ditampilkan sama sekali — nol di
  /// layar akan terbaca sebagai "belum ada yang tersalur", padahal
  /// aplikasinya yang belum tahu.
  bool get _waitingFirstReading => _live && _progress == null;

  /// Mode offline: energi dinaikkan tetap tiap detik.
  void _tick() {
    if (!mounted) return;
    // Tanpa data pembelian, simulasi offline dibatasi nilai wajar.
    final max = widget.session.price?.kwh ?? 20;
    if (_simulatedKwh >= max) {
      _ticker?.cancel();
      return;
    }
    setState(() {
      // Dibulatkan di sini, bukan saat ditampilkan: angka ini karangan
      // aplikasi sendiri, sedangkan [formatEnergy] sengaja mencetak
      // bacaan backend apa adanya. Tanpa pembulatan di sumbernya,
      // penjumlahan 0,4 yang berulang tampil "1,2000000000000002 kWh".
      final next = (_simulatedKwh + _kwhPerTick).clamp(0, max).toDouble();
      _simulatedKwh = (next * 1000).roundToDouble() / 1000;
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
      final progress = await _scope!.repository.fetchChargingProgress(
        orderId: widget.session.orderId,
      );
      // Pengguna sudah masuk alur mengakhiri sesi selagi permintaan ini
      // terbang — jawabannya tidak boleh lagi memindahkan halaman.
      if (!mounted || _ending) return;

      setState(() => _progress = progress);

      if (progress.isFinished) {
        debugPrint('[FLOW] Sesi selesai di charger: $progress');
        _finish(progress.charged);
      }
    } on Object catch (_) {
      // Diabaikan; dicoba lagi pada polling berikutnya.
    } finally {
      _polling = false;
    }
  }

  /// Membuka rincian akhir, menggantikan layar pemantauan.
  ///
  /// Dipanggil dari dua arah — charger yang berhenti sendiri dan
  /// perintah stop dari pengguna — jadi dijaga agar hanya jalan sekali.
  /// Dorongan kedua akan menggusur rute yang salah dan membuat
  /// halamannya tidak bisa ditekan.
  void _finish(double energyKwh) {
    if (_finished || !mounted) return;
    _finished = true;
    _ticker?.cancel();
    // Sesinya sudah tamat; tidak ada lagi yang perlu diingat.
    _scope?.booking.forget();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChargingFinishedPage(session: widget.session, energyKwh: energyKwh),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// "Akhiri Pengisian" — meminta kode sesi lebih dulu.
  ///
  /// Perintah stop **tidak** dikirim di sini. Pengguna harus mengetik
  /// kode sesinya, dan kode itulah yang ikut dikirim ke
  /// `POST /transaction/charging/stop`, sehingga hanya pemilik sesi
  /// yang bisa menghentikan pengisian orang lain.
  Future<void> _stop() async {
    if (_stopping || _finished) return;
    _ending = true;
    _ticker?.cancel();

    final check = await Navigator.of(context).push<SessionCheck>(
      MaterialPageRoute<SessionCheck>(
        builder: (_) => SessionVerificationPage(
          chargeBoxId: widget.session.chargeBox.id,
          connectorId: widget.session.connector.id,
          // Kodenya diteruskan ke /stop; backend yang memutuskan cocok
          // atau tidak, jadi tidak perlu diperiksa dua kali.
          checkWithBackend: false,
        ),
      ),
    );

    if (!mounted) return;

    // Batal menghentikan — pemantauan dijalankan kembali.
    if (check == null) {
      _ending = false;
      _ticker = _startTicker();
      return;
    }

    await _sendStop(check.sessionCode);
  }

  /// Mengirim perintah stop, lalu menunggu angka energi akhirnya.
  Future<void> _sendStop(String sessionCode) async {
    final scope = _scope;

    // Tanpa scope, atau tanpa orderId — sesi yang dilanjutkan dari
    // daftar charge box — tidak ada yang bisa dihentikan lewat backend.
    if (scope == null || widget.session.orderId.isEmpty) {
      debugPrint(
        'Perintah stop DILEWATI: '
        '${scope == null ? 'tidak ada ChargingScope' : 'sesi tanpa orderId'}.',
      );
      _finish(_energyKwh);
      return;
    }

    setState(() => _stopping = true);

    try {
      await scope.repository.stopCharging(
        orderId: widget.session.orderId,
        sessionCode: sessionCode,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(stopErrorMessage(e))));
      // Sesinya masih jalan; pemantauan diteruskan.
      _ending = false;
      _ticker = _startTicker();
      return;
    }

    final energy = await readFinalEnergy(
      repository: scope.repository,
      orderId: widget.session.orderId,
      fallbackKwh: _energyKwh,
    );
    if (!mounted) return;

    _finish(energy);
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
          DangerOutlineButton(
            label: _stopping ? 'Menghentikan…' : 'Akhiri Pengisian',
            onPressed: _stopping ? null : _stop,
          ),
          SecondaryButton(
            label: 'Kembali ke Halaman Awal',
            trailingAsset: 'assets/icons/ic_home_filled.svg',
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: BatteryGauge(fill: _fillRatio),
              ),
            ),
          ),
          if (_waitingFirstReading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: WaitingPanel(label: 'Membaca energi tersalur…'),
            )
          else ...[
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
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Menerjemahkan kegagalan `POST /transaction/charging/stop` jadi
/// arahan yang bisa ditindaklanjuti pengguna.
///
/// Kode sesi yang salah ketik berakhir di sini, karena kode itu ikut
/// dikirim bersama perintah stop dan backend yang menolaknya.
String stopErrorMessage(ApiException e) => switch (e.responseCode) {
  ResponseCode.transactionNotFound =>
    'Kode sesi tidak cocok dengan pengisian ini. Coba masukkan lagi.',
  ResponseCode.noActiveSession =>
    'Tidak ada pengisian yang sedang berjalan di konektor ini.',
  ResponseCode.invalidStatusTransition =>
    'Pengisian ini sedang tidak bisa dihentikan. Coba lagi sebentar.',
  ResponseCode.chargePointOffline =>
    'Charge box sedang tidak terhubung ke controller. Coba lagi sebentar.',
  ResponseCode.chargePointTimedOut =>
    'Charger tidak menjawab tepat waktu. Coba lagi sebentar.',
  _ => generalErrorMessage(e),
};
