import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../models/charging_detail.dart';
import '../models/charging_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';

/// Frame Figma 73:5171 — "Pengisian Selesai".
///
/// Angkanya datang dari `POST /transaction/charging/detail`: energi
/// yang tersalur, nominal yang dibayar, yang terpakai, dan yang
/// dikembalikan. Aplikasi tidak menghitungnya sendiri — hitungan lokal
/// tidak pernah bisa dijamin sama dengan pembukuan backend.
///
/// Selama rinciannya belum datang, dan bila panggilannya gagal atau
/// sesinya tidak punya order (mode offline), yang ditampilkan adalah
/// angka yang sudah dipegang layar sebelumnya.
class ChargingFinishedPage extends StatefulWidget {
  const ChargingFinishedPage({
    super.key,
    required this.session,
    required this.energyKwh,
  });

  final ChargingSession session;
  final double energyKwh;

  @override
  State<ChargingFinishedPage> createState() => _ChargingFinishedPageState();
}

class _ChargingFinishedPageState extends State<ChargingFinishedPage> {
  ChargingDetail? _detail;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;

    final repository = ChargingScope.maybeOf(context)?.repository;
    final orderId = widget.session.orderId;
    if (repository == null || orderId.isEmpty) return;

    () async {
      try {
        final detail = await repository.fetchChargingDetail(orderId: orderId);
        if (!mounted) return;
        debugPrint('[FLOW] Rincian akhir: $detail');

        // Amplop tanpa `data` terurai menjadi nol semua. Memakainya
        // akan menghapus angka yang sudah benar di layar, jadi hanya
        // rincian yang benar-benar berisi yang dipakai.
        if (detail.orderId.isNotEmpty) setState(() => _detail = detail);
      } on Object catch (e) {
        // Angka dari layar sebelumnya tetap ditampilkan; memunculkan
        // error di layar penutup hanya menahan pengguna yang sudah
        // selesai.
        debugPrint('[FLOW] Rincian akhir gagal diambil: $e');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final detail = _detail;

    // Energi dari backend bila ada; kalau tidak, angka terakhir yang
    // dilihat layar pemantauan.
    final energyKwh = detail?.usedKwh ?? widget.energyKwh;
    final paid = detail?.paidAmount ?? session.paidAmount;
    final usage = detail?.usageAmount ?? session.usageCostFor(energyKwh);
    final refund = detail?.refundAmount ?? session.refundFor(energyKwh);

    // Sesi yang dilanjutkan tanpa data pembelian tetap menyembunyikan
    // baris rupiahnya — kecuali backend yang menyebutkan angkanya.
    final hasAmounts = detail != null || session.hasPurchase;

    return PageScaffold(
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: 'Kembali ke Halaman Awal',
            trailingAsset: 'assets/icons/ic_home_filled.svg',
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Center(
            child: AssetSlot(
              'assets/images/finished_check.png',
              width: 180,
              height: 180,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pengisian Selesai',
            textAlign: TextAlign.center,
            style: AppTheme.pageTitle,
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.borderAlt),
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppColors.cardShadow,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DetailRow(
                  label: 'Energi Tersalur',
                  value: formatEnergy(energyKwh),
                  muted: true,
                ),
                // Sesi yang dilanjutkan tidak membawa data pembelian,
                // jadi baris pembayarannya dilewati.
                if (hasAmounts) ...[
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Pembayaran Awal',
                    value: formatRupiah(paid ?? 0),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Total Pemakaian',
                    value: formatRupiah(usage ?? 0),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Sisa Pembayaran',
                    value: formatRupiah(refund ?? 0),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const NoticeBar(
            text: 'Lepas dan kembalikan konektor ke tempatnya',
            asset: 'assets/icons/ic_connector.svg',
          ),
        ],
      ),
    );
  }
}
