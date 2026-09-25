import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../models/reservation.dart';
import '../models/session_check.dart';

import '../app_route_observer.dart';
import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../models/charge_box.dart';
import '../models/charging_session.dart';
import '../models/connector.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/connector_sheet.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/state_view.dart';
import '../widgets/status_chip.dart';
import 'api_config_page.dart';
import 'card_payment_page.dart';
import 'charging_status_page.dart';
import 'session_code_page.dart';
import 'session_verification_page.dart';
import 'transaction_history_page.dart';

/// Frame Figma 70:1901 — "Pilih Charge Box".
///
/// Daftarnya diambil dari `POST /list-chargerbox`. Id charge box dari
/// sini dipakai apa adanya oleh `/start` dan `/stop`, jadi daftar ini
/// harus datang dari backend — bukan data dummy — agar kedua perintah
/// itu mengenai charge box yang benar.
///
/// Daftarnya tidak disegarkan berkala. Pemeriksaan status konektor
/// nanti dilakukan di halaman lain, jadi halaman ini tidak perlu
/// menembak backend terus-menerus. Muat ulang dilakukan lewat
/// tarik-ke-bawah, tombol pada tampilan kosong/gagal, atau otomatis
/// saat pengguna kembali ke sini dari halaman lain.
class ChargeBoxPage extends StatefulWidget {
  /// Key tombol menuju Konfigurasi Server; ikonnya tanpa teks, jadi
  /// test butuh pegangan yang tidak menebak posisinya di pohon widget.
  static const configKey = Key('buka-konfigurasi-server');

  /// Key tombol menuju Riwayat Transaksi, dengan alasan yang sama.
  static const historyKey = Key('buka-riwayat-transaksi');

  const ChargeBoxPage({super.key, this.repository, this.chargeBoxes});

  /// Disuntik di test; produksi memakai instance default.
  final ChargePointRepository? repository;

  /// Melewati pemanggilan jaringan sama sekali — dipakai test widget.
  final List<ChargeBox>? chargeBoxes;

  @override
  State<ChargeBoxPage> createState() => _ChargeBoxPageState();
}

class _ChargeBoxPageState extends State<ChargeBoxPage> with RouteAware {
  List<ChargeBox>? _boxes;
  Object? _error;
  bool _loading = false;

  ChargePointRepository? get _repository =>
      widget.repository ?? ChargingScope.maybeOf(context)?.repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_boxes == null && _error == null && !_loading) _load();

    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// Dipanggil saat rute di atas halaman ini ditutup — pengguna kembali
  /// ke daftar charge box.
  ///
  /// Bottom sheet "Daftar Konektor" juga terhitung rute di atas, jadi
  /// menutupnya ikut memicu pemuatan ulang. Itu disengaja: begitu sheet
  /// hilang, halaman ini terlihat lagi dan datanya harus segar.
  @override
  void didPopNext() {
    debugPrint('[FLOW] Kembali ke Pilih Charge Box — memuat ulang daftar');
    // Pengguna sampai di sini berarti ia keluar dari alur pembelian.
    // Booking yang masih dipegang harus dilepas, kalau tidak
    // konektornya terkunci selamanya.
    unawaited(_cancelAbandonedBooking());
    _load();
  }

  /// Melepas booking yang ditinggalkan pengguna.
  ///
  /// Tidak melakukan apa-apa bila pengisian sudah dimulai: sejak
  /// `/start` berhasil, [ActiveBooking] dilupakan, jadi kembalinya
  /// pengguna ke daftar tidak membatalkan sesi yang sedang jalan.
  ///
  /// Kegagalannya hanya dicatat. Pengguna sudah pergi dari alur itu;
  /// memunculkan error atas sesuatu yang tidak ia minta hanya
  /// membingungkan.
  Future<void> _cancelAbandonedBooking() async {
    final scope = ChargingScope.maybeOf(context);
    final booking = scope?.booking;
    if (scope == null || booking == null || !booking.isHeld) return;

    // Sesi yang sudah mengisi bukan booking yang ditinggalkan —
    // membatalkannya akan menghentikan pengisian orang.
    if (booking.isCharging) return;

    final chargeBoxId = booking.chargeBoxId!;
    final connectorId = booking.connectorId!;
    final reservationId = booking.reservationId ?? '';
    booking.forget();

    try {
      final result = await scope.repository.cancelConnector(
        chargeBoxId: chargeBoxId,
        connectorId: connectorId,
        reservationId: reservationId,
      );
      debugPrint('[FLOW] Booking ditinggalkan, dilepas: $result');
    } on Object catch (e) {
      debugPrint('[FLOW] Booking gagal dilepas: $e');
    }
  }

  /// Memuat daftar. Data lama dipertahankan selama pemuatan berlangsung
  /// supaya muat ulang tidak membuat layar berkedip ke spinner.
  Future<void> _load() async {
    if (_loading) return;

    final fromWidget = widget.chargeBoxes;
    if (fromWidget != null) {
      setState(() {
        _boxes = fromWidget;
        _error = null;
      });
      return;
    }

    final repository = _repository;
    if (repository == null) {
      setState(() {
        _boxes = const [];
        _error = null;
      });
      return;
    }

    _loading = true;
    try {
      final boxes = await repository.fetchChargeBoxes();
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        // Kalau sudah ada data, biarkan tetap tampil; error hanya
        // menggantikan layar ketika belum ada apa-apa.
        _error = e;
      });
    } finally {
      _loading = false;
    }
  }

  Future<void> _openConnectors(ChargeBox box) async {
    final connector = await showConnectorSheet(context, box);
    if (connector == null || !mounted) return;

    // Konektor yang bukan "Available" sudah diklaim, jadi pengguna
    // harus membuktikan kepemilikan sesi lebih dulu dengan kode yang
    // ditunjukkan di halaman "Pengisian Dimulai".
    var verifiedOrderId = '';
    Reservation? reservation;

    if (!connector.isAvailable) {
      final expected = ChargingScope.maybeOf(
        context,
      )?.booking.sessionCodeOn(chargeBoxId: box.id, connectorId: connector.id);

      final check = await Navigator.of(context).push<SessionCheck>(
        MaterialPageRoute<SessionCheck>(
          builder: (_) => SessionVerificationPage(
            chargeBoxId: box.id,
            connectorId: connector.id,
            expectedCode: expected,
          ),
        ),
      );
      if (check == null || !mounted) return;
      verifiedOrderId = check.orderId;
      // Konektor yang sudah dipesan orang lain dilanjutkan dengan
      // pemesanan yang sudah ada, bukan dipesan ulang.
      reservation = Reservation(
        accepted: true,
        reservationId: check.reservationId,
        sessionCode: check.sessionCode,
      );
    } else {
      // Konektor bebas: pesan dulu atas nama pengguna ini sebelum ia
      // menghabiskan waktu memilih nominal dan membayar.
      reservation = await _book(box, connector);
      if (reservation == null || !mounted) return;
    }

    // Tujuannya ditentukan status konektor: yang masih bebas memulai
    // pembelian, sisanya melanjutkan sesi yang sudah dipegang orang —
    // masing-masing pada langkah tempat sesi itu berhenti.
    final destination = switch (connector.status) {
      // Kode sesinya ditunjukkan dulu — pengguna memerlukannya untuk
      // kembali ke sesi ini. "Dipesan" berarti pemesanan sudah ada
      // tetapi belum dibeli, jadi jalurnya sama.
      ConnectorStatus.available || ConnectorStatus.reserved => SessionCodePage(
        chargeBox: box,
        connector: connector,
        reservation: reservation,
      ),
      // Ordernya sudah dibuat tetapi belum dibayar: sesinya dilanjutkan
      // di halaman pembayaran, dan nominalnya ditanyakan ulang lewat
      // inquiry begitu kartu ditempelkan.
      ConnectorStatus.awaitingPayment => CardPaymentPage(
        session: _resume(box, connector, verifiedOrderId),
      ),
      ConnectorStatus.inUse => ChargingStatusPage(
        session: _resume(box, connector, verifiedOrderId),
      ),
      // Status tak dikenal tidak bisa ditekan, jadi cabang ini tak
      // terpakai.
      ConnectorStatus.unavailable => null,
    };
    if (destination == null) return;

    debugPrint(
      '[FLOW] Konektor ${connector.id} berstatus ${connector.statusCode} — '
      'menuju ${destination.runtimeType}',
    );

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => destination));
    // Pemuatan ulang ditangani didPopNext saat rute di atas ditutup.
  }

  /// Memesan konektor lewat `POST /booked-connector`.
  ///
  /// Mengembalikan null bila konektornya baru saja diambil orang lain
  /// atau permintaannya gagal — dua-duanya berarti alur tidak boleh
  /// lanjut.
  Future<Reservation?> _book(ChargeBox box, Connector connector) async {
    final repository = _repository;

    // Mode offline: pemesanan ditiru supaya alurnya tetap bisa diuji.
    if (repository == null) {
      return Reservation(accepted: true, sessionCode: Env.sessionPin);
    }

    // Diambil sebelum await: sesudahnya context belum tentu masih hidup.
    final booking = ChargingScope.maybeOf(context)?.booking;

    try {
      final reservation = await repository.bookConnector(
        chargeBoxId: box.id,
        connectorId: connector.id,
      );
      debugPrint('[FLOW] Pemesanan: $reservation');
      if (reservation.accepted) {
        booking?.hold(
          chargeBoxId: box.id,
          connectorId: connector.id,
          reservationId: reservation.reservationId,
          sessionCode: reservation.sessionCode,
        );
        return reservation;
      }
    } on ApiException catch (e) {
      _complain(e.message);
      return null;
    } on Object catch (e) {
      _complain('Konektor gagal dipesan: $e');
      return null;
    }

    _complain(
      '${connector.name} baru saja diambil pengguna lain. '
      'Silakan pilih konektor lain.',
    );
    // Daftarnya sudah basi kalau konektor ini ternyata sudah terpakai.
    _load();
    return null;
  }

  void _complain(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sesi tanpa data pembelian — aplikasi tidak tahu berapa yang sudah
  /// dibayarkan pengguna sebelumnya.
  ///
  /// orderId-nya diambil dari ingatan unit ini.
  ///
  /// `POST /manage-sessioncode` membuktikan kode sesinya benar tetapi
  /// tidak mengirim ordernya, sedangkan semua perintah pengisian
  /// berkunci order. Akibatnya sesi yang dimulai dari unit lain belum
  /// bisa dipantau maupun dihentikan dari sini. Tanpa itu kemajuannya tidak
  /// bisa ditanyakan dan pengisiannya tidak bisa dihentikan, karena
  /// semua endpoint pengisian berkunci order.
  ChargingSession _resume(
    ChargeBox box,
    Connector connector,
    String verifiedOrderId,
  ) {
    final remembered = ChargingScope.maybeOf(
      context,
    )?.booking.orderOn(chargeBoxId: box.id, connectorId: connector.id);

    return ChargingSession.resumed(
      chargeBox: box,
      connector: connector,
      now: DateTime.now(),
      orderId: verifiedOrderId.isNotEmpty ? verifiedOrderId : remembered ?? '',
    );
  }

  /// Kembali ke halaman Konfigurasi Server.
  ///
  /// Memakai pushReplacement supaya halaman ini tidak menumpuk di bawah
  /// config — tombol "Kembali ke Halaman Awal" di halaman-halaman
  /// lanjutan memulangkan ke rute pertama, dan rute pertama harus tetap
  /// daftar charge box, bukan layar konfigurasi.
  /// Riwayat seluruh konektor di lokasi ini.
  ///
  /// Daftarnya diambil dari layar ini apa adanya: halaman riwayat
  /// menanyakan tiap konektor sendiri, dan tanpa daftar itu ia tidak
  /// tahu harus menanyakan apa.
  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionHistoryPage(chargeBoxes: _boxes ?? const []),
      ),
    );
  }

  void _openConfig() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ApiConfigPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pilih Charge Box',
      subtitle: 'Pastikan sama dengan nomor tempat parkir',
      showStation: true,
      isHome: true,
      // Alamat controller bisa diubah lagi tanpa menutup aplikasi.
      // Dua tombol: riwayat transaksi lalu konfigurasi server. Riwayat
      // dibuka dari sini karena hanya halaman ini yang memegang seluruh
      // charge box — endpoint riwayat meminta konektornya satu per satu.
      headerAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleIconButton(
            key: ChargeBoxPage.historyKey,
            asset: 'assets/icons/ic_receipt.svg',
            onTap: _openHistory,
          ),
          const SizedBox(width: 8),
          CircleIconButton(
            key: ChargeBoxPage.configKey,
            asset: 'assets/icons/ic_settings.svg',
            onTap: _openConfig,
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final boxes = _boxes;

    if (boxes == null) {
      return _error == null
          ? const StateView.loading()
          : _ErrorState(error: _error!, onRetry: _load);
    }

    if (boxes.isEmpty) {
      return StateView(
        icon: Icons.ev_station_outlined,
        title: 'Belum ada charge box',
        message:
            'Tidak ada charge box yang terdaftar di lokasi ini. '
            'Tarik ke bawah untuk memuat ulang.',
        onRetry: _load,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: boxes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final box = boxes[index];
        return ChargeBoxCard(
          chargeBox: box,
          onTap: box.isAvailable ? () => _openConnectors(box) : null,
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;

    return StateView(
      icon: api?.isNetworkIssue ?? false
          ? Icons.wifi_off_rounded
          : Icons.error_outline_rounded,
      title: 'Gagal memuat charge box',
      message: api?.message ?? 'Terjadi kesalahan yang tidak dikenali.',
      onRetry: onRetry,
      retryLabel: 'Coba Lagi',
    );
  }
}

/// Kartu 70:1917 — putih, radius 16, padding 12, dengan ornamen sudut
/// kanan bawah dan badge nomor bergradient.
class ChargeBoxCard extends StatelessWidget {
  const ChargeBoxCard({super.key, required this.chargeBox, this.onTap});

  final ChargeBox chargeBox;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = chargeBox.isAvailable;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            const Positioned(
              right: 0,
              bottom: 0,
              child: AssetSlot(
                'assets/images/card_corner.svg',
                width: 108,
                height: 46,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _NumberBadge(text: chargeBox.badge, enabled: enabled),
                      const SizedBox(width: 12),
                      Expanded(child: _CardBody(chargeBox: chargeBox)),
                      if (enabled) ...[
                        const SizedBox(width: 12),
                        CircleIconButton(
                          asset: 'assets/icons/ic_chevron.svg',
                          size: 32,
                          onTap: onTap,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.chargeBox});

  final ChargeBox chargeBox;

  @override
  Widget build(BuildContext context) {
    final enabled = chargeBox.isAvailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          chargeBox.name,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.cardTitle.copyWith(
            color: enabled ? AppColors.title : AppColors.titleDisabled,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            AssetSlot(
              enabled
                  ? 'assets/icons/ic_plug.svg'
                  : 'assets/icons/ic_plug_disabled.svg',
              width: 16,
              height: 16,
            ),
            const SizedBox(width: 4),
            Text(
              chargeBox.connectorLabel,
              style: AppTheme.cardCaption.copyWith(
                color: enabled ? AppColors.icon : AppColors.iconDisabled,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(width: 8),
              const StatusChip.unavailable(),
            ],
          ],
        ),
      ],
    );
  }
}

/// Badge 70:1920 — 44x44, radius 12, gradient 135°, angka Inter Bold 20.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.text, required this.enabled});

  final String text;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: enabled
            ? AppColors.badgeGradient
            : AppColors.badgeDisabledGradient,
        borderRadius: BorderRadius.circular(12),
        border: enabled ? null : Border.all(color: AppColors.badgeBorder),
      ),
      child: Text(
        text,
        style: AppTheme.badgeNumber.copyWith(
          color: enabled ? Colors.white : AppColors.titleDisabled,
        ),
      ),
    );
  }
}
