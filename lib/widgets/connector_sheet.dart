import 'dart:async';

import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../models/charge_box.dart';
import '../models/connector.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';
import 'status_chip.dart';

/// Membuka bottom sheet 70:2480 dan mengembalikan konektor yang dipilih,
/// atau null bila sheet ditutup tanpa memilih.
Future<Connector?> showConnectorSheet(BuildContext context, ChargeBox box) {
  return showModalBottomSheet<Connector>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ConnectorSheet(chargeBox: box),
  );
}

/// Isi bottom sheet.
///
/// Status konektor tidak terlihat dari daftar charge box, jadi begitu
/// sheet ini terbuka isinya diambil ulang lewat
/// `POST /detail-chargerbox` — satu panggilan untuk seluruh konektor,
/// bukan satu per konektor. Tidak ada polling: statusnya cukup
/// diperiksa saat pengguna membukanya.
///
/// Tanpa [ChargingScope] — mode offline untuk test — status dari daftar
/// dipakai apa adanya.
class _ConnectorSheet extends StatefulWidget {
  const _ConnectorSheet({required this.chargeBox});

  final ChargeBox chargeBox;

  @override
  State<_ConnectorSheet> createState() => _ConnectorSheetState();
}

class _ConnectorSheetState extends State<_ConnectorSheet> {
  late List<Connector> _connectors = widget.chargeBox.connectors;
  bool _checking = false;
  bool _checked = false;

  ChargeBox get chargeBox => widget.chargeBox;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    unawaited(_checkStatuses());
  }

  /// Mengambil isi charge box ini sekali, berikut status konektornya.
  ///
  /// Kegagalan memakai data dari daftar apa adanya — lebih baik
  /// daripada mengosongkan sheet karena satu permintaan meleset.
  Future<void> _checkStatuses() async {
    final repository = ChargingScope.maybeOf(context)?.repository;
    if (repository == null) return;

    setState(() => _checking = true);

    try {
      final detail = await repository.fetchChargeBoxDetail(
        chargeBoxId: chargeBox.id,
        number: chargeBox.number,
      );
      if (!mounted) return;

      debugPrint(
        '[FLOW] Detail ${chargeBox.id}: '
        '${detail.connectors.map((c) => '${c.id}=${c.statusCode}').join(', ')}',
      );

      // Detail tanpa konektor tidak boleh mengosongkan sheet — yang
      // dari daftar lebih berguna daripada layar kosong.
      if (detail.connectors.isNotEmpty) {
        setState(() => _connectors = detail.connectors);
      }
    } on Object catch (e) {
      debugPrint('[FLOW] Detail ${chargeBox.id} gagal diambil: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header 70:2481 — padding 16/16/16/8.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daftar Konektor', style: AppTheme.sheetTitle),
                      const SizedBox(height: 4),
                      Text(
                        '${chargeBox.badge} · ${chargeBox.name}',
                        style: AppTheme.sheetSubtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CircleIconButton(
                  asset: 'assets/icons/ic_close.svg',
                  showBorder: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Content 70:2487 — padding 16, gap 16.
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemCount: _connectors.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final connector = _connectors[index];
                return _ConnectorCard(
                  connector: connector,
                  chargeBox: chargeBox,
                  checking: _checking,
                  // Selama status sebenarnya belum datang, konektornya
                  // belum boleh dipilih — tujuannya ditentukan status.
                  onTap: !_checking && connector.isSelectable
                      ? () => Navigator.of(context).pop(connector)
                      : null,
                );
              },
            ),
          ),
          // Drawer 70:2526 — home indicator.
          SizedBox(
            height: 21,
            child: Center(
              child: Container(
                width: 135,
                height: 5,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: AppColors.homeIndicator,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Kartu 70:2488 — border #E4EFF7, radius 16, padding 12.
class _ConnectorCard extends StatelessWidget {
  const _ConnectorCard({
    required this.connector,
    required this.chargeBox,
    required this.checking,
    this.onTap,
  });

  final Connector connector;

  /// Charge box dari daftar — `POST /detail-chargerbox` tidak mengirim
  /// `daya`, jadi keterangannya diambil dari sini.
  final ChargeBox chargeBox;
  final bool checking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadowSoft,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.connectorIconGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const AssetSlot(
                    'assets/icons/ic_connector_ccs2.svg',
                    width: 24,
                    height: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(connector.name, style: AppTheme.cardTitle),
                      // "CCS2 - 200 kW DC" — tipe dan arus dari
                      // konektor, dayanya dari charge box.
                      if (connector.typeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          connector.describeWith(chargeBox.daya),
                          style: AppTheme.cardCaption.copyWith(
                            color: AppColors.description,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      _StatusRow(connector: connector, checking: checking),
                    ],
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

/// Baris status: chip sesuai kondisi konektor, plus estimasi selesai
/// bila backend mengirimnya.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.connector, required this.checking});

  final Connector connector;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'Memeriksa…',
          background: AppColors.infoTileBg,
          foreground: AppColors.description,
        ),
      );
    }

    final chip = switch (connector.status) {
      ConnectorStatus.reserved => const StatusChip.reserved(),
      ConnectorStatus.available => const StatusChip.available(),
      ConnectorStatus.inUse => const StatusChip.inUse(),
      ConnectorStatus.awaitingPayment => const StatusChip.awaitingPayment(),
      // "Tidak tersedia", termasuk angka yang tak dikenal. Angka mentahnya
      // tercatat di log untuk teknisi; pengguna cukup tahu konektornya
      // tidak bisa dipakai.
      ConnectorStatus.unavailable => const StatusChip(
        label: 'Tidak Tersedia',
        background: AppColors.unavailableBg,
        foreground: AppColors.unavailableFg,
      ),
    };

    final estimate = connector.estimatedMinutes;
    if (estimate == null) {
      return Align(alignment: Alignment.centerLeft, child: chip);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        chip,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AssetSlot('assets/icons/ic_clock.svg', width: 16, height: 16),
            const SizedBox(width: 4),
            Text(
              'Est. $estimate menit',
              style: AppTheme.cardCaption.copyWith(
                color: AppColors.description,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
