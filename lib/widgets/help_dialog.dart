import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/charging_scope.dart';
import '../models/help_contact.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';
import 'primary_button.dart';
import 'status_chip.dart';

/// Modal "Butuh Bantuan?".
///
/// Kontaknya datang dari `GET /evtap/bantuan` — bukan angka yang
/// ditanam di aplikasi — supaya nomor yang berubah cukup diperbarui di
/// backend. Tiap baris bisa disalin, dan nomor WhatsApp-nya sekalian
/// dijadikan QR supaya pengguna tinggal memindai dengan ponselnya
/// alih-alih menyalin dari layar kios.
Future<void> showHelpDialog(BuildContext context) => showDialog<void>(
  context: context,
  // Ditutup lewat tombolnya, bukan gesture kembali perangkat.
  barrierDismissible: false,
  builder: (_) => const _HelpDialog(),
);

class _HelpDialog extends StatefulWidget {
  const _HelpDialog();

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  HelpContact? _contact;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_contact != null || _error != null) return;

    final repository = ChargingScope.maybeOf(context)?.repository;
    if (repository == null) {
      // Mode offline: tidak ada yang bisa ditanyakan.
      setState(() => _contact = const HelpContact());
      return;
    }

    repository
        .fetchHelpContact()
        .then((contact) {
          if (mounted) setState(() => _contact = contact);
        })
        .onError((error, _) {
          if (mounted) setState(() => _error = 'Kontak bantuan gagal diambil.');
        });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        // Modalnya tetap ramping di layar lebar; barisnya jadi sulit
        // dibaca kalau melar selebar layar kios.
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.cardShadow,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CircleIconButton(
                  asset: 'assets/icons/ic_close.svg',
                  showBorder: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const AssetSlot(
                  'assets/icons/ic_support.svg',
                  width: 44,
                  height: 44,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Butuh Bantuan?',
                textAlign: TextAlign.center,
                style: AppTheme.sheetTitle,
              ),
              const SizedBox(height: 4),
              const Text(
                'Tim kami siap membantu Anda.',
                textAlign: TextAlign.center,
                style: AppTheme.pageSubtitle,
              ),
              const SizedBox(height: 16),
              _Body(contact: _contact, error: _error),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Tutup',
                trailingAsset: null,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isi modal: daftar kontak, atau keterangan saat belum/tidak ada.
class _Body extends StatelessWidget {
  const _Body({required this.contact, required this.error});

  final HelpContact? contact;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error case final message?) {
      return Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: AppColors.unavailableFg),
      );
    }

    final contact = this.contact;
    if (contact == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (contact.isEmpty) {
      return const Text(
        'Hubungi petugas di lokasi — kontak bantuan belum diatur.',
        textAlign: TextAlign.center,
        style: AppTheme.pageSubtitle,
      );
    }

    return Column(
      children: [
        if (contact.email.isNotEmpty)
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: contact.email,
          ),
        if (contact.hotline.isNotEmpty)
          _ContactRow(
            icon: Icons.call_rounded,
            label: 'Hotline',
            value: contact.hotline,
          ),
        if (contact.whatsapp.isNotEmpty)
          _ContactRow(
            icon: Icons.chat_rounded,
            label: 'WhatsApp',
            value: contact.whatsapp,
            // Hijau WhatsApp, seperti di desain.
            tint: const Color(0xFF25D366),
          ),
        if (contact.whatsappLink.isNotEmpty) ...[
          const SizedBox(height: 4),
          _WhatsappQr(link: contact.whatsappLink),
        ],
      ],
    );
  }
}

/// Satu baris kontak dengan tombol salin.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.tint,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Warna ikonnya; null memakai biru lembut bawaan.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint ?? AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: tint == null ? AppColors.primary : Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.rowLabel),
                Text(value, style: AppTheme.rowValue),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Salin $label',
            icon: const Icon(Icons.copy_rounded, size: 20),
            color: AppColors.description,
            onPressed: () => _copy(context),
          ),
        ],
      ),
    );
  }

  /// Menyalin nilainya; kios tidak punya papan ketik, jadi menyalin
  /// jauh lebih masuk akal daripada meminta pengguna mengetik ulang.
  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label disalin.')));
  }
}

/// Blok QR chat WhatsApp.
class _WhatsappQr extends StatelessWidget {
  const _WhatsappQr({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.infoTileBg,
        border: Border.all(color: AppColors.borderAlt),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          QrImageView(
            data: link,
            size: 96,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.all(6),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan QR untuk\nchat via WhatsApp',
                  style: AppTheme.rowValue,
                ),
                SizedBox(height: 4),
                Text(
                  'Dapatkan bantuan lebih cepat melalui WhatsApp.',
                  style: AppTheme.pageSubtitle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
