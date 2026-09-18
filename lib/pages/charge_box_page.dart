import 'dart:async';

import 'package:flutter/material.dart';

import '../app_route_observer.dart';
import '../config/env.dart';
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
import 'charging_status_page.dart';
import 'nominal_page.dart';
import 'session_verification_page.dart';

/// Frame Figma 70:1901 — "Pilih Charge Box".
///
/// Daftarnya diambil dari `GET /list`. Id charge point dari sini
/// dipakai apa adanya oleh `/start` dan `/stop`, jadi daftar ini harus
/// datang dari backend — bukan data dummy — agar kedua perintah itu
/// mengenai charger yang benar.
///
/// Tombol refresh di header sudah dihapus, jadi muat ulang dilakukan
/// lewat tarik-ke-bawah atau tombol pada tampilan kosong/gagal.
class ChargeBoxPage extends StatefulWidget {
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
  Timer? _refreshTimer;

  ChargePointRepository? get _repository =>
      widget.repository ?? ChargingScope.maybeOf(context)?.repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_boxes == null && _error == null && !_loading) _load();

    // Daftar disegarkan berkala selama halaman ini terlihat, karena
    // charger bisa tersambung atau terputus kapan saja.
    _refreshTimer ??= Timer.periodic(
      Env.listRefreshInterval,
      (_) => _refreshIfVisible(),
    );

    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
    debugPrint('[FLOW] Kembali ke Pilih Charge Box — memuat ulang /list');
    _load();
  }

  void _refreshIfVisible() {
    // Jangan menembak backend saat halaman ini tertutup halaman lain.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    _load();
  }

  /// Memuat daftar. Data lama dipertahankan selama pemuatan berlangsung
  /// supaya penyegaran berkala tidak membuat layar berkedip ke spinner.
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

    // Konektor yang bukan "Available" sudah diklaim orang lain, jadi
    // pengguna harus membuktikan kepemilikan sesi lebih dulu.
    if (!connector.isAvailable) {
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const SessionVerificationPage(),
        ),
      );
      if (verified != true || !mounted) return;
    }

    // Tujuannya ditentukan status konektor. "Preparing" diperlakukan
    // sama seperti "Available" — belum ada transaksi, jadi pengguna
    // tetap membeli dulu. Hanya konektor yang sudah mengisi yang
    // melanjutkan ke layar pemantauan.
    final destination = switch (connector.status) {
      ConnectorStatus.available || ConnectorStatus.preparing => NominalPage(
          chargeBox: box,
          connector: connector,
        ),
      ConnectorStatus.inUse => ChargingStatusPage(
          session: _resume(box, connector),
        ),
      // Konektor rusak tidak bisa ditekan, jadi cabang ini tak terpakai.
      ConnectorStatus.unavailable => null,
    };
    if (destination == null) return;

    debugPrint(
      '[FLOW] Konektor ${connector.id} berstatus ${connector.rawStatus} — '
      'menuju ${destination.runtimeType}',
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
    // Pemuatan ulang ditangani didPopNext saat rute di atas ditutup.
  }

  /// Sesi tanpa data pembelian — aplikasi tidak tahu berapa yang sudah
  /// dibayarkan pengguna sebelumnya.
  ChargingSession _resume(ChargeBox box, Connector connector) {
    return ChargingSession.resumed(
      chargeBox: box,
      connector: connector,
      transactionId: connector.session?.transactionId,
      now: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pilih Charge Box',
      subtitle: 'Pastikan sama dengan nomor tempat parkir',
      showStation: true,
      isHome: true,
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
        message: 'Tidak ada charger yang sedang terhubung ke controller. '
            'Daftar diperbarui otomatis.',
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
