import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../data/formatters.dart';
import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/nominal_option.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import 'confirmation_page.dart';

/// Frame Figma 70:2231 — "Pilih Nominal".
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
  // Mengikuti desain: Rp50.000 sudah terpilih saat halaman dibuka.
  NominalOption _selected = DemoData.nominals[1];

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConfirmationPage(
          chargeBox: widget.chargeBox,
          connector: widget.connector,
          nominal: _selected,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pilih Nominal',
      subtitle: 'Pilih nominal pengisian sesuai kebutuhan Anda.',
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        children: [
          PrimaryButton(label: 'Lanjutkan', onPressed: _continue),
          SecondaryButton(
            label: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _NominalGrid(
            selected: _selected,
            onSelect: (nominal) => setState(() => _selected = nominal),
          ),
          const SizedBox(height: 16),
          PriceBreakdownCard(nominal: _selected),
        ],
      ),
    );
  }
}

/// Grid 2 kolom, gap 8 (70:2244).
class _NominalGrid extends StatelessWidget {
  const _NominalGrid({required this.selected, required this.onSelect});

  final NominalOption selected;
  final ValueChanged<NominalOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < DemoData.nominals.length; row += 2)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 8),
            child: Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _NominalCard(
                      nominal: DemoData.nominals[row + col],
                      selected:
                          DemoData.nominals[row + col].amount == selected.amount,
                      onTap: () => onSelect(DemoData.nominals[row + col]),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Kartu nominal 70:2246 — radius 12, px 10, py 12, gap 8.
class _NominalCard extends StatelessWidget {
  const _NominalCard({
    required this.nominal,
    required this.selected,
    required this.onTap,
  });

  final NominalOption nominal;
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
                    formatRupiah(nominal.amount),
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

/// Kartu "Rincian Harga" 70:2283 — radius 12, padding 12, gap 12.
class PriceBreakdownCard extends StatelessWidget {
  const PriceBreakdownCard({super.key, required this.nominal});

  final NominalOption nominal;

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
          CostRows(nominal: nominal),
          const SizedBox(height: 12),
          TotalRow(amount: nominal.total),
        ],
      ),
    );
  }
}
