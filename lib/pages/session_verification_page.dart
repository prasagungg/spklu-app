import 'package:flutter/material.dart';

import '../config/env.dart';
import '../data/charging_scope.dart';
import '../models/session_check.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_slot.dart';
import '../widgets/help_dialog.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';

/// Frame Figma 73:4752 — "Verifikasi Sesi".
///
/// Ditampilkan sebelum pengguna boleh menyentuh konektor yang statusnya
/// bukan "Available": konektor itu sudah diklaim, jadi hanya pemilik
/// sesi — yang memegang kode sesi dari halaman "Pengisian Dimulai" —
/// yang boleh melanjutkan.
///
/// Kodenya diperiksa backend lewat `POST /manage-sessioncode`. Kode
/// sesi melekat pada order, jadi aplikasi tidak bisa — dan tidak boleh
/// — memutuskannya sendiri.
///
/// Mengembalikan [SessionCheck] lewat Navigator bila kodenya benar,
/// atau null bila pengguna membatalkan.
class SessionVerificationPage extends StatefulWidget {
  /// Key tombol hapus pada keypad, dipakai test.
  static const eraseKey = Key('keypad-erase');

  const SessionVerificationPage({
    super.key,
    required this.chargeBoxId,
    required this.connectorId,
    this.expectedCode,
    this.checkWithBackend = true,
  });

  final String chargeBoxId;
  final int connectorId;

  /// Kode yang diterima saat tidak ada backend — mode offline untuk
  /// test. Default [Env.sessionPin].
  final String? expectedCode;

  /// Memeriksa kode lewat `POST /manage-sessioncode` sebelum menutup
  /// halaman.
  ///
  /// Dimatikan saat kode dikumpulkan untuk perintah lain yang sudah
  /// membawanya sendiri — `POST /transaction/charging/stop` ikut
  /// menerima `sessionCode` dan backend yang menolak bila salah, jadi
  /// memeriksanya dua kali hanya menambah satu perjalanan jaringan.
  final bool checkWithBackend;

  @override
  State<SessionVerificationPage> createState() =>
      _SessionVerificationPageState();
}

class _SessionVerificationPageState extends State<SessionVerificationPage> {
  /// Desain menyediakan dua kotak digit.
  static const _length = 2;

  String _entered = '';
  bool _wrong = false;
  bool _checking = false;

  /// Alasan penolakan dari backend, bila ada.
  String? _reason;

  String get _expected => widget.expectedCode ?? Env.sessionPin;

  bool get _complete => _entered.length == _length;

  void _press(String digit) {
    if (_complete || _checking) return;
    setState(() {
      _entered += digit;
      _wrong = false;
      _reason = null;
    });
  }

  void _erase() {
    if (_entered.isEmpty || _checking) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _wrong = false;
      _reason = null;
    });
  }

  Future<void> _verify() async {
    if (_checking) return;

    // Kode hanya dikumpulkan; yang memeriksanya perintah berikutnya.
    if (!widget.checkWithBackend) {
      Navigator.of(context).pop(SessionCheck(sessionCode: _entered));
      return;
    }

    final repository = ChargingScope.maybeOf(context)?.repository;

    // Mode offline: tidak ada yang bisa memeriksa, jadi dibandingkan
    // dengan kode yang diketahui aplikasi.
    if (repository == null) {
      if (_entered == _expected) {
        Navigator.of(context).pop(SessionCheck(sessionCode: _entered));
        return;
      }
      _reject();
      return;
    }

    setState(() => _checking = true);

    try {
      final check = await repository.verifySessionCode(
        chargeBoxId: widget.chargeBoxId,
        connectorId: widget.connectorId,
        sessionCode: _entered,
      );
      if (!mounted) return;
      debugPrint('[FLOW] Kode sesi diterima: $check');
      Navigator.of(context).pop(check);
    } on ApiException catch (e) {
      _reject(
        e.responseCode == ResponseCode.transactionNotFound
            ? 'Kode sesi tidak cocok, atau sesinya sudah berakhir'
            : e.message,
      );
    } on Object catch (e) {
      _reject('Kode gagal diperiksa: $e');
    }
  }

  void _reject([String? reason]) {
    if (!mounted) return;
    setState(() {
      _wrong = true;
      _checking = false;
      _entered = '';
      _reason = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Verifikasi Sesi',
      subtitle: switch ((_checking, _wrong)) {
        (true, _) => 'Memeriksa kode sesi…',
        (_, true) => _reason ?? 'Kode sesi salah, coba lagi',
        _ => 'Masukkan $_length digit kode sesi',
      },
      titleAlign: TextAlign.center,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: _checking ? 'Memeriksa…' : 'Verifikasi',
            trailingAsset: null,
            onPressed: _complete && !_checking ? _verify : null,
          ),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Kembali',
                  leadingAsset: 'assets/icons/ic_arrow_left.svg',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Bantuan',
                  onPressed: () => showHelpDialog(context),
                ),
              ),
            ],
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SessionDigitBoxes(entered: _entered, length: _length, wrong: _wrong),
          const SizedBox(height: 16),
          SessionKeypad(onDigit: _press, onErase: _erase),
        ],
      ),
    );
  }
}

/// Dua kotak digit (73:4866). Kotak yang sedang diisi bergaris biru;
/// yang kosong menampilkan kursor.
class SessionDigitBoxes extends StatelessWidget {
  const SessionDigitBoxes({
    super.key,
    required this.entered,
    required this.length,
    required this.wrong,
  });

  final String entered;
  final int length;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          _DigitBox(
            digit: i < entered.length ? entered[i] : null,
            active: i == entered.length,
            wrong: wrong,
          ),
        ],
      ],
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({
    required this.digit,
    required this.active,
    required this.wrong,
  });

  final String? digit;
  final bool active;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    final borderColor = wrong
        ? AppColors.unavailableFg
        : digit != null || active
        ? AppColors.pinActiveBorder
        : AppColors.borderAlt;

    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadowSoft,
      ),
      child: digit != null
          ? Text(
              digit!,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: AppColors.value,
                letterSpacing: 2.4,
              ),
            )
          : Text(
              active ? '|' : '',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
                letterSpacing: 1.3,
              ),
            ),
    );
  }
}

/// Keypad 73:4878 — tiga baris angka, lalu 0 dan tombol hapus.
class SessionKeypad extends StatelessWidget {
  const SessionKeypad({
    super.key,
    required this.onDigit,
    required this.onErase,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onErase;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ]) ...[
          Row(
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _KeyButton(digit: row[i], onTap: onDigit),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            // Slot kosong di kiri, mengikuti desain.
            const Expanded(child: SizedBox(height: 52)),
            const SizedBox(width: 12),
            Expanded(
              child: _KeyButton(digit: '0', onTap: onDigit),
            ),
            const SizedBox(width: 12),
            Expanded(child: _EraseButton(onTap: onErase)),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.digit, required this.onTap});

  final String digit;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.keypadBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadowSoft,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(digit),
          child: SizedBox(
            height: 52,
            child: Center(
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.value,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EraseButton extends StatelessWidget {
  const _EraseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.keypadEraseBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.eraseShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Tombol ini tidak punya teks, jadi diberi key agar bisa
          // ditemukan test tanpa menebak posisinya di pohon widget.
          key: SessionVerificationPage.eraseKey,
          onTap: onTap,
          child: const SizedBox(
            height: 52,
            child: Center(
              child: AssetSlot(
                'assets/icons/ic_backspace.svg',
                width: 34,
                height: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
