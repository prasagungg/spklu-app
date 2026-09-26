import 'package:flutter/material.dart';

import '../config/env.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../data/charging_scope.dart';
import '../widgets/password_dialog.dart';
import '../widgets/spklu_code_dialog.dart';
import '../widgets/status_chip.dart';
import 'api_config_page.dart';
import 'master_charge_box_page.dart';

/// Meminta password, lalu membuka halaman Pengaturan bila cocok.
///
/// Dipanggil dari lima ketukan pada logo di header — lihat
/// `PageScaffold`. Salah password tidak membuka apa pun dan tidak
/// meninggalkan jejak di layar.
Future<void> openSettings(BuildContext context) async {
  if (!await showPasswordDialog(context)) return;
  if (!context.mounted) return;

  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
}

/// Halaman Pengaturan perangkat — layar petugas, bukan pengguna.
///
/// Isinya pengaturan perangkat — SAM Card, kode SPKLU, uji transaksi —
/// dan **Konfigurasi Server** (alamat edge controller), yang dulu punya
/// tombol sendiri di header halaman Pilih Charge Box.
class SettingsPage extends StatelessWidget {
  /// Key kartu menuju Konfigurasi Server, dipakai test.
  static const serverKey = Key('buka-konfigurasi-server');

  /// Key kartu "Input Kode SPKLU", dipakai test.
  static const spkluCodeKey = Key('buka-kode-spklu');

  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pengaturan',
      subtitle: 'Kelola perangkat dan pengaturan SPKLU',
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _SettingsTile(
                  icon: Icons.credit_card,
                  title: 'Konfigurasi SAM Card',
                  subtitle: 'Atur parameter dan konfigurasi SAM Card',
                ),
                _SettingsTile(
                  icon: Icons.manage_search,
                  title: 'Pengecekan SAM Card',
                  subtitle: 'Periksa keadaan SAM Card yang terpasang',
                ),
                _SettingsTile(
                  key: SettingsPage.spkluCodeKey,
                  icon: Icons.dialpad,
                  title: 'Input Kode SPKLU',
                  subtitle: 'Masukkan kode SPKLU untuk menghubungkan perangkat',
                  onTap: _openSpkluCode,
                ),
                _SettingsTile(
                  icon: Icons.point_of_sale,
                  title: 'Tes Transaksi',
                  subtitle: 'Pastikan perangkat berfungsi dengan baik',
                ),
                _SettingsTile(
                  key: SettingsPage.serverKey,
                  icon: Icons.dns_outlined,
                  title: 'Konfigurasi Server',
                  subtitle: 'Atur alamat edge controller yang dipakai unit ini',
                  onTap: (context) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ApiConfigPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _VersionFootnote(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Menanyakan kode SPKLU, lalu membuka daftar charge box CSMS-nya.
///
/// Tanpa repository — mode offline untuk test — kartunya berperilaku
/// seperti kartu yang belum punya tujuan: tidak ada yang bisa ditanya.
Future<void> _openSpkluCode(BuildContext context) async {
  final repository = ChargingScope.maybeOf(context)?.repository;
  if (repository == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server belum dikonfigurasi.')),
    );
    return;
  }

  final spklu = await showSpkluCodeDialog(context, repository);
  if (spklu == null || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MasterChargeBoxPage(spklu: spklu, repository: repository),
    ),
  );
}

/// Satu baris menu: ikon berlatar lembut, judul, keterangan, chevron.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Tujuan kartu ini. Kosong berarti layarnya belum ada.
  final void Function(BuildContext context)? onTap;

  /// Kartu tanpa tujuan menjelaskan keadaannya alih-alih diam saja.
  void _open(BuildContext context) {
    final destination = onTap;
    if (destination != null) {
      destination(context);
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title belum tersedia.')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 28, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTheme.cardTitle),
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppTheme.cardCaption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleIconButton(
                    asset: 'assets/icons/ic_chevron.svg',
                    size: 32,
                    onTap: () => _open(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionFootnote extends StatelessWidget {
  const _VersionFootnote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AssetSlot(
            'assets/icons/ic_info_circle.svg',
            width: 20,
            height: 20,
          ),
          const SizedBox(width: 6),
          // Fleksibel: nomor versi yang panjang tidak boleh meluber
          // keluar layar.
          Flexible(
            child: Text(
              'SPKLU Dual Mode · Versi ${Env.appVersion}',
              style: AppTheme.pageSubtitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
