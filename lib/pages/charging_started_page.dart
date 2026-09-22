import 'package:flutter/material.dart';

import '../models/charging_session.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';

/// Frame Figma 73:3667 — "Pengisian Dimulai".
///
/// Muncul setelah perintah start berhasil, dan satu-satunya tempat kode
/// sesi ditampilkan besar. Kodenya datang dari
/// `POST /transaction/push-order` — pengguna memerlukannya untuk
/// mengakhiri sesinya nanti, jadi inilah alasan layar ini ada.
///
/// Satu-satunya jalan keluarnya adalah pulang ke daftar charge box,
/// mengikuti desain. Untuk memantau atau menghentikan pengisiannya,
/// pengguna menekan konektornya lagi dari daftar itu dan memasukkan
/// kode sesi ini.
class ChargingStartedPage extends StatelessWidget {
  const ChargingStartedPage({super.key, required this.session});

  final ChargingSession session;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pengisian Dimulai',
      subtitle: session.breadcrumb,
      titleAlign: TextAlign.center,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: 'Kembali ke Halaman Awal',
            trailingAsset: 'assets/icons/ic_home_filled.svg',
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          const _Footnote(),
        ],
      ),
      child: Column(
        children: [
          const Expanded(
            child: AssetSlot(
              'assets/images/charging_car.png',
              fit: BoxFit.contain,
            ),
          ),
          const HintStrip(text: 'Pengisian sedang berlangsung...'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SessionCodeCard(code: session.sessionCode),
          ),
        ],
      ),
    );
  }
}

/// Kartu kode sesi (73:3708) — latar #EEF7FE, angka Inter Bold 48.
class _SessionCodeCard extends StatelessWidget {
  const _SessionCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.sessionCardBg,
        border: Border.all(color: AppColors.sessionCardBorder),
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
                'assets/images/session_corner_a.svg',
                width: 130,
                height: 56,
              ),
            ),
            const Positioned(
              left: 0,
              bottom: 0,
              child: AssetSlot(
                'assets/images/session_corner_b.svg',
                width: 97,
                height: 42,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              child: Column(
                children: [
                  const Text(
                    'Simpan Kode Sesi Anda',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.description,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: AppColors.title,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Kode ini diperlukan untuk mengakhiri sesi.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.description,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Pengisian tetap berjalan." (73:3732)
class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AssetSlot('assets/icons/ic_info_circle.svg', width: 20, height: 20),
        SizedBox(width: 6),
        Text(
          'Pengisian tetap berjalan.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.icon,
          ),
        ),
      ],
    );
  }
}
