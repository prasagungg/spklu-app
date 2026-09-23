import 'package:flutter/material.dart';

import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/transaction_history.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/state_view.dart';

/// Riwayat transaksi satu konektor, dari
/// `POST /transaction/history-transaction`.
///
/// Dibuka dari kartu konektor di bottom sheet "Daftar Konektor" —
/// satu-satunya tempat nomor charge box dan konektornya sama-sama ada
/// di tangan, dan itulah yang diminta endpoint-nya.
class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    super.key,
    required this.chargeBox,
    required this.connector,
  });

  final ChargeBox chargeBox;
  final Connector connector;

  @override
  State<TransactionHistoryPage> createState() =>
      _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  List<TransactionHistoryEntry>? _entries;
  Object? _error;

  ChargePointRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entries != null || _error != null) return;

    _repository = ChargingScope.maybeOf(context)?.repository;
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;

    // Tanpa backend tidak ada riwayat yang bisa ditampilkan; daftar
    // kosong lebih jujur daripada data karangan.
    if (repository == null) {
      setState(() => _entries = const []);
      return;
    }

    try {
      final entries = await repository.fetchTransactionHistory(
        chargeBoxId: widget.chargeBox.id,
        connectorId: widget.connector.id,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Riwayat Transaksi',
      subtitle: '${widget.chargeBox.badge} • ${widget.chargeBox.name} • '
          '${widget.connector.name}',
      backgroundColor: AppColors.pageBackgroundPlain,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final entries = _entries;

    if (entries == null) {
      return _error == null
          ? const StateView(
              title: 'Memuat riwayat…',
              message: 'Mengambil transaksi pada konektor ini.',
            )
          : StateView(
              icon: Icons.error_outline_rounded,
              title: 'Gagal memuat riwayat',
              message: _error is ApiException
                  ? (_error! as ApiException).message
                  : 'Terjadi kesalahan yang tidak dikenali.',
              onRetry: _load,
              retryLabel: 'Coba Lagi',
            );
    }

    if (entries.isEmpty) {
      return StateView(
        icon: Icons.receipt_long_outlined,
        title: 'Belum ada transaksi',
        message: 'Konektor ini belum pernah dipakai mengisi daya.',
        onRetry: _load,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => TransactionHistoryCard(
        chargeBox: widget.chargeBox,
        connector: widget.connector,
        entry: entries[index],
      ),
    );
  }
}

/// Kartu riwayat 189:761.
///
/// Judul dan tipe konektor datang dari konteks — riwayat dibuka untuk
/// satu konektor tertentu, dan backend tidak mengulang namanya di tiap
/// entri.
class TransactionHistoryCard extends StatelessWidget {
  const TransactionHistoryCard({
    super.key,
    required this.chargeBox,
    required this.connector,
    required this.entry,
  });

  final ChargeBox chargeBox;
  final Connector connector;
  final TransactionHistoryEntry entry;

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
          Text(
            '${chargeBox.badge} - ${chargeBox.name}',
            overflow: TextOverflow.ellipsis,
            style: AppTheme.cardTitle,
          ),
          const SizedBox(height: 4),
          Text(
            // "CCS2 - 200 kW DC" seperti desain; dayanya milik charge
            // box, bukan konektornya.
            connector.describeWith(chargeBox.daya),
            style: AppTheme.cardCaption.copyWith(color: AppColors.icon),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1, color: AppColors.borderAlt),
          const SizedBox(height: 8),
          _IconDetail(
            asset: 'assets/icons/ic_clock.svg',
            text: formatDateTime(entry.createdAt),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _IconDetail(
                asset: 'assets/icons/ic_money.svg',
                text: formatRupiah(entry.totalAmount),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: _IconDetail(
                  asset: 'assets/images/ic_wallet.png',
                  text: entry.maskedCard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ikon 16x16 dengan teks di sebelahnya, jarak 4 (189:766).
class _IconDetail extends StatelessWidget {
  const _IconDetail({required this.asset, required this.text});

  final String asset;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AssetSlot(asset, width: 16, height: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.cardCaption.copyWith(color: AppColors.description),
          ),
        ),
      ],
    );
  }
}
