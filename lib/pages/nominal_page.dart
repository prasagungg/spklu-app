import 'package:flutter/material.dart';

import '../data/booking_progress.dart';
import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../data/demo_data.dart';
import '../data/formatters.dart';
import '../models/booking.dart';
import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/kwh_price.dart';
import '../models/order.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/state_view.dart';
import 'confirmation_page.dart';

/// Frame Figma 70:2231 — "Pilih Nominal".
///
/// Pilihan kWh datang dari `GET /list-kwh`, dan harganya dari
/// `POST /count-kwh` begitu salah satu dipilih. Keduanya milik backend:
/// halaman ini tidak menghitung apa pun.
///
/// **Tidak ada yang terpilih saat halaman dibuka.** Pilihan yang sudah
/// tercentang sejak awal gampang terlewat, dan pengguna bisa membayar
/// jumlah yang tidak pernah ia pilih sendiri.
class NominalPage extends StatefulWidget {
  const NominalPage({
    super.key,
    required this.chargeBox,
    required this.connector,
  });

  final ChargeBox chargeBox;
  final Connector connector;

  @override
  State<NominalPage> createState() => _NominalPageState();
}

class _NominalPageState extends State<NominalPage> {
  List<double>? _options;
  Object? _error;

  double? _selected;
  KwhPrice? _price;

  /// Harga sedang dihitung backend untuk pilihan yang baru ditekan.
  bool _counting = false;

  /// Order sedang dibuat setelah "Lanjutkan" ditekan.
  bool _pushing = false;

  ChargePointRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_options != null || _error != null) return;

    _repository = ChargingScope.maybeOf(context)?.repository;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final repository = _repository;

    // Mode offline: pilihan dan harganya ditiru lokal.
    if (repository == null) {
      setState(() => _options = DemoData.kwhOptions);
      return;
    }

    try {
      final options = await repository.fetchKwhOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Menghitung harga pilihan yang baru ditekan.
  ///
  /// Pilihannya langsung ditandai supaya tekanan jari terasa dibalas,
  /// sementara rincian harganya menyusul.
  Future<void> _select(double kwh) async {
    if (_counting) return;

    setState(() {
      _selected = kwh;
      _price = null;
      _counting = true;
    });

    final repository = _repository;
    if (repository == null) {
      setState(() {
        _price = DemoData.priceFor(kwh);
        _counting = false;
      });
      return;
    }

    try {
      final price = await repository.countKwh(
        chargeBoxId: widget.chargeBox.id,
        connectorId: widget.connector.id,
        kwh: kwh,
      );
      if (!mounted) return;
      setState(() {
        _price = price;
        _counting = false;
      });
    } on ApiException catch (e) {
      _failCount(e.message);
    } on Object catch (e) {
      _failCount('Harga gagal dihitung: $e');
    }
  }

  void _failCount(String message) {
    if (!mounted) return;
    setState(() => _counting = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Membuat order di backend, lalu maju ke halaman konfirmasi.
  ///
  /// Ordernya dibuat di sini — bukan setelah pembayaran — karena
  /// nomor referensi dan kode sesi yang ditampilkan halaman berikutnya
  /// datang dari sana.
  Future<void> _continue() async {
    final price = _price;
    if (price == null || _pushing) return;

    // Nominal sudah dipilih: ordernya sedang dibuat.
    reportBookingStage(
      context,
      chargeBoxId: widget.chargeBox.id,
      connectorId: widget.connector.id,
      stage: BookingStage.ordering,
    );

    final repository = _repository;
    if (repository == null) {
      _openConfirmation(DemoData.orderFor(price));
      return;
    }

    setState(() => _pushing = true);

    try {
      final order = await repository.pushOrder(
        chargeBoxId: widget.chargeBox.id,
        connectorId: widget.connector.id,
        kwh: price.kwh,
      );
      if (!mounted) return;
      setState(() => _pushing = false);
      debugPrint('[FLOW] Order dibuat: $order');
      _openConfirmation(order);
    } on ApiException catch (e) {
      _failPush(orderErrorMessage(e));
    } on Object catch (e) {
      _failPush('Order gagal dibuat: $e');
    }
  }

  void _openConfirmation(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConfirmationPage(
          chargeBox: widget.chargeBox,
          connector: widget.connector,
          order: order,
        ),
      ),
    );
  }

  void _failPush(String message) {
    if (!mounted) return;
    setState(() => _pushing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final price = _price;

    return PageScaffold(
      title: 'Pilih Nominal',
      subtitle: 'Pilih jumlah kWh sesuai kebutuhan Anda.',
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        children: [
          PrimaryButton(
            label: switch ((_counting, _pushing)) {
              (true, _) => 'Menghitung…',
              (_, true) => 'Memproses…',
              _ => 'Lanjutkan',
            },
            // Mati sampai ada harga: tanpa itu tidak ada yang bisa
            // dikonfirmasi di halaman berikutnya.
            onPressed: price == null || _pushing ? null : _continue,
          ),
          SecondaryButton(
            label: 'Kembali',
            onPressed: _pushing ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      child: _body(price),
    );
  }

  Widget _body(KwhPrice? price) {
    final options = _options;

    if (options == null) {
      return _error == null
          ? const StateView(
              title: 'Memuat pilihan kWh…',
              message: 'Mengambil daftar pembelian dari server.',
            )
          : StateView(
              icon: Icons.error_outline_rounded,
              title: 'Gagal memuat pilihan kWh',
              message: _error is ApiException
                  ? (_error! as ApiException).message
                  : 'Terjadi kesalahan yang tidak dikenali.',
              onRetry: _loadOptions,
              retryLabel: 'Coba Lagi',
            );
    }

    if (options.isEmpty) {
      return StateView(
        icon: Icons.bolt_outlined,
        title: 'Belum ada pilihan kWh',
        message: 'Server tidak mengirim satu pun pilihan pembelian.',
        onRetry: _loadOptions,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _KwhGrid(options: options, selected: _selected, onSelect: _select),
        const SizedBox(height: 16),
        if (price != null)
          PriceBreakdownCard(price: price)
        else
          _PricePlaceholder(counting: _counting),
      ],
    );
  }
}

/// Grid 2 kolom, gap 8 (70:2244).
class _KwhGrid extends StatelessWidget {
  const _KwhGrid({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<double> options;
  final double? selected;
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < options.length; row += 2)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 8),
            child: Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row + col < options.length
                        ? _KwhCard(
                            kwh: options[row + col],
                            selected: options[row + col] == selected,
                            onTap: () => onSelect(options[row + col]),
                          )
                        // Baris ganjil: sisi kanan dibiarkan kosong agar
                        // kartu terakhir tidak melebar sendiri.
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Kartu pilihan 70:2246 — radius 12, px 10, py 12, gap 8.
class _KwhCard extends StatelessWidget {
  const _KwhCard({
    required this.kwh,
    required this.selected,
    required this.onTap,
  });

  final double kwh;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? null : AppColors.surface,
        gradient: selected ? AppColors.nominalSelectedGradient : null,
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: selected ? AppColors.selectedShadow : AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primarySoft.withValues(alpha: 0.3)
                        : AppColors.primarySoft,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white),
                  ),
                  child: AssetSlot(
                    selected
                        ? 'assets/icons/ic_money_active.svg'
                        : 'assets/icons/ic_money.svg',
                    width: 16,
                    height: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatKwh(kwh),
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.nominalLabel.copyWith(
                      color: selected ? Colors.white : AppColors.title,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Menggantikan kartu rincian sebelum ada yang dipilih.
class _PricePlaceholder extends StatelessWidget {
  const _PricePlaceholder({required this.counting});

  final bool counting;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Text(
        counting
            ? 'Menghitung harga…'
            : 'Pilih jumlah kWh di atas untuk melihat rincian harganya.',
        textAlign: TextAlign.center,
        style: AppTheme.pageSubtitle,
      ),
    );
  }
}

/// Kartu "Rincian Harga" 70:2283 — radius 12, padding 12, gap 12.
class PriceBreakdownCard extends StatelessWidget {
  const PriceBreakdownCard({super.key, required this.price});

  final KwhPrice price;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rincian Harga', style: AppTheme.cardTitle),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: AppColors.borderAlt),
          const SizedBox(height: 12),
          CostRows(price: price),
          const SizedBox(height: 12),
          TotalRow(amount: price.rpTotal),
        ],
      ),
    );
  }
}

/// Menerjemahkan kegagalan `POST /transaction/push-order` jadi arahan
/// yang bisa ditindaklanjuti pengguna.
String orderErrorMessage(ApiException e) => switch (e.responseCode) {
  ResponseCode.processingAnotherRequest =>
    'Masih ada pesanan yang belum selesai di konektor ini. '
        'Tunggu sebentar atau pilih konektor lain.',
  ResponseCode.invalidStatusTransition =>
    'Konektor ini sedang dalam keadaan yang tidak menerima pesanan '
        'baru. Kembali dan pilih konektor lain.',
  _ => generalErrorMessage(e),
};
