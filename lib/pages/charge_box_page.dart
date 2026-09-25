import 'dart:async';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../models/reservation.dart';
import '../models/session_check.dart';

import '../app_route_observer.dart';
import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../models/backend_status.dart';
import '../models/charge_box.dart';
import '../models/charging_session.dart';
import '../models/order.dart';
import '../models/connector.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/connector_sheet.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/state_view.dart';
import '../widgets/status_chip.dart';
import 'charging_finished_page.dart';
import 'connect_connector_page.dart';
import 'confirmation_page.dart';
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
  /// Key tombol menuju Riwayat Transaksi; ikonnya tanpa teks, jadi test
  /// butuh pegangan yang tidak menebak posisinya di pohon widget.
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
    // Pemesanan dilepas oleh halaman yang ditinggalkan pengguna — Kode
    // Sesi dan Pilih Nominal, satu-satunya langkah sebelum order dibuat.
    // Halaman ini juga dilewati saat pengguna kembali dari Riwayat
    // Transaksi, Pengaturan, atau alur yang sudah punya order, jadi ia
    // tidak boleh ikut membatalkan.
    _load();
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
    // ditunjukkan saat sesinya dimulai.
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

      // Tahap transaksinya yang menentukan tujuan, bukan status
      // konektor: `statusProcess` menyebut sampai mana sesi itu
      // berjalan, dan pengguna dikembalikan tepat ke langkah itu.
      final destination = await _resumeDestination(box, connector, check);
      if (destination == null || !mounted) return;

      debugPrint(
        '[FLOW] statusProcess ${check.statusProcess} — '
        'menuju ${destination.runtimeType}',
      );
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => destination));

      // Pemesanan dilepas oleh halaman Kode Sesi, satu-satunya tempat
      // pengguna membatalkan sebelum apa pun dibeli.
      //
      // Pemuatan ulang ditangani didPopNext saat rute di atas ditutup.
      return;
    }

    // Konektor bebas: pesan dulu atas nama pengguna ini sebelum ia
    // menghabiskan waktu memilih nominal dan membayar.
    final reservation = await _book(box, connector);
    if (reservation == null || !mounted) return;

    // Kode sesinya ditunjukkan dulu — pengguna memerlukannya untuk
    // kembali ke sesi ini.
    final destination = SessionCodePage(
      chargeBox: box,
      connector: connector,
      reservation: reservation,
    );

    debugPrint(
      '[FLOW] Konektor ${connector.id} dipesan — '
      'menuju ${destination.runtimeType}',
    );

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => destination));
    // Pemuatan ulang ditangani didPopNext saat rute di atas ditutup.
  }

  /// Halaman tempat sesi yang sudah berjalan dilanjutkan, ditentukan
  /// `statusProcess` pada jawaban `POST /manage-sessioncode`.
  ///
  /// | `statusProcess` | Tahap | Halaman |
  /// |---|---|---|
  /// | 0 | pemesanan | Konfirmasi Pengisian |
  /// | 1 | belum bayar | Konfirmasi Pengisian |
  /// | 2 | hubungkan konektor | Hubungkan Konektor |
  /// | 3 | proses pengisian | Sedang Mengisi |
  /// | 4 | pengisian selesai | Pengisian Selesai |
  ///
  /// Order yang belum dibayar dikembalikan ke konfirmasi, bukan langsung
  /// ke pembaca kartu: pengguna perlu melihat lagi apa yang akan
  /// dibayarnya sebelum menempelkan kartu.
  ///
  /// Angka yang tidak dikenal — termasuk jawaban tanpa `statusProcess` —
  /// ikut ke konfirmasi, langkah paling awal yang masih bisa
  /// dilanjutkan tanpa menebak apa pun.
  Future<Widget?> _resumeDestination(
    ChargeBox box,
    Connector connector,
    SessionCheck check,
  ) async {
    final session = _resume(box, connector, check);

    return switch (check.statusProcess) {
      BackendStatus.awaitingConnector => ConnectConnectorPage(session: session),
      BackendStatus.charging => ChargingStatusPage(session: session),
      // Angka energinya diambil halaman itu sendiri lewat
      // `charging/detail`; nol hanya nilai awal sebelum jawabannya tiba.
      BackendStatus.finished => ChargingFinishedPage(
        session: session,
        energyKwh: 0,
      ),
      // 0 pemesanan, 1 belum bayar, dan angka yang tidak dikenal.
      _ => await _confirmationFor(box, connector, session),
    };
  }

  /// Halaman konfirmasi untuk sesi yang ordernya sudah dibuat tetapi
  /// belum dikonfirmasi.
  ///
  /// Rincian ordernya tidak ikut di jawaban `manage-sessioncode`, jadi
  /// diambil lewat `POST /transaction/charging/detail`. Bila ordernya
  /// tidak bisa dibaca — belum ada, atau permintaannya gagal — pengguna
  /// diantar ke halaman pembayaran alih-alih ditahan di layar kosong.
  Future<Widget?> _confirmationFor(
    ChargeBox box,
    Connector connector,
    ChargingSession session,
  ) async {
    final repository = _repository;
    if (repository == null || session.orderId.isEmpty) {
      return CardPaymentPage(session: session);
    }

    try {
      final detail = await repository.fetchChargingDetail(
        orderId: session.orderId,
      );
      if (detail.orderId.isEmpty) return CardPaymentPage(session: session);

      return ConfirmationPage(
        chargeBox: box,
        connector: connector,
        order: Order(
          orderId: detail.orderId,
          sessionCode: session.sessionCode,
          partnerReference: session.reference,
          kwh: detail.orderedKwh,
          rpTotal: detail.paidAmount,
          rpPerKwh: detail.pricePerKwh,
        ),
      );
    } on Object catch (e) {
      debugPrint('[FLOW] Rincian order gagal dibaca: $e');
      return CardPaymentPage(session: session);
    }
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
    SessionCheck check,
  ) {
    final remembered = ChargingScope.maybeOf(
      context,
    )?.booking.orderOn(chargeBoxId: box.id, connectorId: connector.id);

    return ChargingSession.resumed(
      chargeBox: box,
      connector: connector,
      now: DateTime.now(),
      sessionCode: check.sessionCode,
      orderId: check.orderId.isNotEmpty ? check.orderId : remembered ?? '',
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

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pilih Charge Box',
      subtitle: 'Pastikan sama dengan nomor tempat parkir',
      showStation: true,
      isHome: true,
      // Riwayat transaksi dibuka dari sini karena hanya halaman ini yang
      // memegang seluruh charge box — endpoint riwayat meminta
      // konektornya satu per satu.
      //
      // Konfigurasi Server tidak lagi punya tombol di sini; ia pindah ke
      // halaman Pengaturan, bersama pengaturan perangkat lainnya.
      headerAction: CircleIconButton(
        key: ChargeBoxPage.historyKey,
        asset: 'assets/icons/ic_receipt.svg',
        onTap: _openHistory,
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
