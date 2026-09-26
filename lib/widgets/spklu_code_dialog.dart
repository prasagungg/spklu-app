import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/charge_point_repository.dart';
import '../models/spklu.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'primary_button.dart';
import 'status_chip.dart';

/// Modal "Kode SPKLU".
///
/// Menanyakan kode SPKLU lalu menanyakannya ke
/// `POST /master/list-chargerbox`. Mengembalikan SPKLU beserta charge
/// boxnya bila ada isinya, null bila petugas membatalkan.
///
/// Jawaban kosong tidak menutup modal: kodenya kemungkinan salah ketik,
/// jadi petugas dibiarkan memperbaikinya di tempat.
Future<Spklu?> showSpkluCodeDialog(
  BuildContext context,
  ChargePointRepository repository,
) => showDialog<Spklu>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SpkluCodeDialog(repository: repository),
);

class _SpkluCodeDialog extends StatefulWidget {
  const _SpkluCodeDialog({required this.repository});

  final ChargePointRepository repository;

  @override
  State<_SpkluCodeDialog> createState() => _SpkluCodeDialogState();
}

class _SpkluCodeDialogState extends State<_SpkluCodeDialog> {
  late final _controller = TextEditingController(text: Env.idSpklu);

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Kode SPKLU belum diisi.');
      return;
    }
    if (_sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final spklu = await widget.repository.fetchMasterSpklu(idSpklu: code);
      if (!mounted) return;

      if (spklu.chargeBoxes.isEmpty) {
        setState(() {
          _sending = false;
          _error = 'Tidak ada charge box untuk kode itu.';
        });
        return;
      }

      Navigator.of(context).pop(spklu);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Daftar charge box gagal diambil: $e';
      });
    }
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
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            const Text(
              'Kode SPKLU',
              textAlign: TextAlign.center,
              style: AppTheme.sheetTitle,
            ),
            const SizedBox(height: 4),
            const Text(
              'Masukkan kode SPKLU untuk melihat charge box yang '
              'terdaftar di CSMS.',
              textAlign: TextAlign.center,
              style: AppTheme.pageSubtitle,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: 'SPKLU-SMR',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.unavailableFg,
                ),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: _sending ? 'Mengirim…' : 'Kirim',
              trailingAsset: null,
              onPressed: _sending ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
