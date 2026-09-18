import 'package:flutter/material.dart';

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

class _ConnectorSheet extends StatelessWidget {
  const _ConnectorSheet({required this.chargeBox});

  final ChargeBox chargeBox;

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
              itemCount: chargeBox.connectors.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final connector = chargeBox.connectors[index];
                return _ConnectorCard(
                  connector: connector,
                  onTap: connector.isSelectable
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
  const _ConnectorCard({required this.connector, this.onTap});

  final Connector connector;
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
                      const SizedBox(height: 6),
                      _StatusRow(connector: connector),
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
  const _StatusRow({required this.connector});

  final Connector connector;

  @override
  Widget build(BuildContext context) {
    final chip = switch (connector.status) {
      ConnectorStatus.available => const StatusChip.available(),
      ConnectorStatus.preparing => const StatusChip.preparing(),
      ConnectorStatus.inUse => const StatusChip.inUse(),
      // Reserved / Unavailable / Faulted — status OCPP mentahnya
      // ditampilkan supaya teknisi tahu penyebabnya.
      ConnectorStatus.unavailable => StatusChip(
        label: connector.errorCode != 'NoError'
            ? connector.errorCode
            : connector.rawStatus,
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
