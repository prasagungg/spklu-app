import 'package:flutter/material.dart';

import '../config/env.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';
import 'primary_button.dart';
import 'status_chip.dart';

/// Modal "Akses Pengaturan".
///
/// Mengembalikan true bila password yang diketik cocok, false bila
/// pengguna membatalkan. Passwordnya diperiksa di sini dan tidak pernah
/// dibawa keluar — pemanggil hanya tahu boleh atau tidak.
Future<bool> showPasswordDialog(BuildContext context) async {
  final granted = await showDialog<bool>(
    context: context,
    // Ditutup lewat tombol X atau "Batal", sama seperti halaman lain
    // yang tidak menerima gesture kembali perangkat.
    barrierDismissible: false,
    builder: (_) => const _PasswordDialog(),
  );

  return granted ?? false;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  /// Password disembunyikan sampai ikon mata ditekan.
  bool _hidden = true;
  bool _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == Env.settingsPassword) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _wrong = true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.cardShadow,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CircleIconButton(
                asset: 'assets/icons/ic_close.svg',
                showBorder: false,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const AssetSlot(
              'assets/images/ic_session_lock.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 12),
            const Text(
              'Akses Pengaturan',
              textAlign: TextAlign.center,
              style: AppTheme.sheetTitle,
            ),
            const SizedBox(height: 4),
            const Text(
              'Masukkan password untuk mengakses pengaturan perangkat',
              textAlign: TextAlign.center,
              style: AppTheme.pageSubtitle,
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _controller,
              hidden: _hidden,
              wrong: _wrong,
              onToggle: () => setState(() => _hidden = !_hidden),
              onChanged: (_) {
                if (_wrong) setState(() => _wrong = false);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_wrong) ...[
              const SizedBox(height: 8),
              const Text(
                'Password salah. Coba lagi.',
                style: TextStyle(fontSize: 12, color: AppColors.unavailableFg),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Masuk',
              trailingAsset: null,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Batal',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.hidden,
    required this.wrong,
    required this.onToggle,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool hidden;
  final bool wrong;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: wrong ? AppColors.unavailableFg : AppColors.border,
      ),
    );

    return TextField(
      controller: controller,
      obscureText: hidden,
      autofocus: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: AppTheme.cardTitle,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: wrong ? AppColors.unavailableFg : AppColors.primary,
          ),
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.icon,
          ),
        ),
      ),
    );
  }
}
