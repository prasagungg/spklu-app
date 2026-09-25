import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/charging_session.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/session_widgets.dart';
import 'charging_status_page.dart';

/// Frame Figma 204:5174 (sebelumnya 73:3667) — "Pengisian Dimulai".
///
/// Muncul setelah perintah start berhasil dan mengulang kode sesi
/// sekali lagi, lalu **berpindah sendiri** ke layar pemantauan.
///
/// Charger butuh beberapa detik sebelum melaporkan kWh pertamanya —
/// controller hanya meneruskan perintah start, jadi `ongoing-kwh` masih
/// menjawab nol sesaat. Halaman ini mengisi jeda itu: ia menahan
/// pengguna [_minWait]–[_maxWait] detik sambil menunjukkan kode sesi,
/// baru kemudian membuka `ChargingStatusPage`.
///
/// **Ini layar tunggu, jadi tidak ada tombol aksi.** Satu-satunya jalan
/// keluar lebih awal adalah tombol Home di header, yang dipasang
/// `PageScaffold` di semua halaman; pengisian jalan terus di charger.
class ChargingStartedPage extends StatefulWidget {
  const ChargingStartedPage({super.key, required this.session, this.waitFor});

  final ChargingSession session;

  /// Lama menahan sebelum pindah. Kosong berarti diacak
  /// [_minWait]–[_maxWait] detik; diisi hanya oleh test supaya
  /// hasilnya tidak bergantung pada angka acak.
  final Duration? waitFor;

  @override
  State<ChargingStartedPage> createState() => _ChargingStartedPageState();
}

class _ChargingStartedPageState extends State<ChargingStartedPage> {
  static const _minWait = 2;
  static const _maxWait = 4;

  Timer? _advance;

  ChargingSession get session => widget.session;

  @override
  void initState() {
    super.initState();

    final wait =
        widget.waitFor ??
        Duration(seconds: _minWait + Random().nextInt(_maxWait - _minWait + 1));
    debugPrint('[FLOW] Pengisian Dimulai menahan ${wait.inSeconds} detik');

    _advance = Timer(wait, _openStatus);
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  /// Berpindah ke layar pemantauan, menggantikan halaman ini supaya
  /// tombol kembali tidak memulangkan ke layar tunggu.
  void _openStatus() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChargingStatusPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pengisian Dimulai',
      subtitle: session.breadcrumb,
      titleAlign: TextAlign.center,
      backgroundColor: AppColors.pageBackgroundPlain,
      // Tidak ada tombol: halaman ini berpindah sendiri, jadi tidak ada
      // yang perlu ditekan pengguna.
      child: Column(
        children: [
          const Expanded(
            child: AssetSlot(
              'assets/images/charging_car.png',
              fit: BoxFit.contain,
            ),
          ),
          // Panel tunggu yang sama dengan "Menunggu Kartu" dan
          // "Menunggu konektor terdeteksi" — spinner berputar selama
          // charger menyiapkan sesinya.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: WaitingPanel(label: 'Menyiapkan pengisian…'),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SessionCodeCard(code: session.sessionCode),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Kartu kode sesi (73:3708) — latar #EEF7FE, angka Inter Bold 48.
class SessionCodeCard extends StatelessWidget {
  const SessionCodeCard({super.key, required this.code});

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              // Anak Stack yang tidak diposisikan hanya selebar isinya
              // dan menempel ke kiri; tanpa lebar penuh, kode sesinya
              // terlihat bergeser dari tengah kartu.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Simpan Kode Sesi Anda',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.description,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    code,
                    textAlign: TextAlign.center,
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
                    textAlign: TextAlign.center,
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
