import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/charging_scope.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';
import 'primary_button.dart';
import 'status_chip.dart';

/// Modal "Akses Pengaturan".
///
/// Mengembalikan true bila backend menerima kredensialnya, false bila
/// pengguna membatalkan. Kredensialnya diperiksa `POST /login` dan tidak
/// pernah dibawa keluar — pemanggil hanya tahu boleh atau tidak.
///
/// Dialognya tetap terbuka selama backend menolak: yang salah ketik bisa
/// membetulkannya di tempat, dan alasan penolakannya datang dari backend
/// sendiri, bukan tebakan aplikasi.
Future<bool> showLoginDialog(BuildContext context) async {
  final granted = await showDialog<bool>(
    context: context,
    // Ditutup lewat tombol X atau "Batal", sama seperti halaman lain
    // yang tidak menerima gesture kembali perangkat.
    barrierDismissible: false,
    builder: (_) => const _LoginDialog(),
  );

  return granted ?? false;
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  /// Password disembunyikan sampai ikon mata ditekan.
  bool _hidden = true;
  bool _checking = false;

  /// Alasan penolakan, apa adanya dari backend.
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      !_checking;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final repository = ChargingScope.maybeOf(context)?.repository;

    // Tanpa scope tidak ada backend untuk ditanya — demo dan test.
    // Produksi selalu punya scope, jadi jalur ini tidak pernah lewat di
    // perangkat sungguhan.
    if (repository == null) {
      if (_password.text == Env.settingsPassword) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = 'Password salah. Coba lagi.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      await repository.login(
        username: _username.text.trim(),
        password: _password.text,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = e.message;
      });
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Tidak bisa menghubungi server: $e';
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CircleIconButton(
                  asset: 'assets/icons/ic_close.svg',
                  showBorder: false,
                  onTap: _checking
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              const AssetSlot(
                'assets/images/ic_session_lock.png',
                width: 96,
                height: 96,
              ),
              const SizedBox(height: 12),
              const Text(
                'Akses Pengaturan',
                textAlign: TextAlign.center,
                style: AppTheme.sheetTitle,
              ),
              const SizedBox(height: 4),
              const Text(
                'Masuk dengan akun edge controller untuk mengakses '
                'pengaturan perangkat',
                textAlign: TextAlign.center,
                style: AppTheme.pageSubtitle,
              ),
              const SizedBox(height: 16),
              _LoginField(
                key: const Key('login-username-field'),
                controller: _username,
                hint: 'Username',
                enabled: !_checking,
                wrong: _error != null,
                onChanged: (value) {
                  _clearError(value);
                  setState(() {});
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              _LoginField(
                key: const Key('login-password-field'),
                controller: _password,
                hint: 'Password',
                enabled: !_checking,
                wrong: _error != null,
                obscure: _hidden,
                onToggle: () => setState(() => _hidden = !_hidden),
                onChanged: (value) {
                  _clearError(value);
                  setState(() {});
                },
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.unavailableFg,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                label: _checking ? 'Memeriksa…' : 'Masuk',
                trailingAsset: null,
                onPressed: _canSubmit ? _submit : null,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Batal',
                onPressed: _checking
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Satu kolom modal ini: username polos, password bisa dibuka-tutup.
class _LoginField extends StatelessWidget {
  const _LoginField({
    super.key,
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.wrong,
    required this.onChanged,
    required this.onSubmitted,
    this.obscure = false,
    this.onToggle,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;

  /// Backend menolak kredensialnya — kedua kolom ikut memerah, karena
  /// yang ditolak pasangannya, bukan salah satunya.
  final bool wrong;

  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool obscure;

  /// Ada berarti kolomnya bisa dibuka-tutup lewat ikon mata.
  final VoidCallback? onToggle;

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
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: AppTheme.cardTitle,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.mutedLabel,
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: wrong ? AppColors.unavailableFg : AppColors.primary,
          ),
        ),
        suffixIcon: onToggle == null
            ? null
            : IconButton(
                onPressed: enabled ? onToggle : null,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.icon,
                ),
              ),
      ),
    );
  }
}
