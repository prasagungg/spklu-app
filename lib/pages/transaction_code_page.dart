import 'package:flutter/material.dart';

import '../data/charging_scope.dart';
import '../models/transaction_detail.dart';
import '../models/transaction_history.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import 'session_verification_page.dart';

/// Kode sesi sebelum rincian satu transaksi riwayat dibuka.
///
/// Riwayat boleh dilihat siapa saja yang berdiri di depan unit ini —
/// isinya hanya waktu, nominal, dan nomor kartu yang disamarkan.
/// Rinciannya tidak: `POST /transaction/detail-history-transaction`
/// mewajibkan kode sesi, dan itulah yang membuktikan transaksinya
/// memang milik penanya.
///
/// Keypadnya sama dengan Verifikasi Sesi — hanya yang diperiksa yang
/// berbeda, jadi kotak digit dan tombol angkanya dipakai ulang.
///
/// Mengembalikan [TransactionDetail] lewat Navigator bila kodenya
/// benar, atau null bila pengguna membatalkan.
class TransactionCodePage extends StatefulWidget {
  const TransactionCodePage({super.key, required this.entry});

  final TransactionHistoryEntry entry;

  @override
  State<TransactionCodePage> createState() => _TransactionCodePageState();
}

class _TransactionCodePageState extends State<TransactionCodePage> {
  /// Desain menyediakan dua kotak digit, sama seperti Verifikasi Sesi.
  static const _length = 2;

  String _entered = '';
  bool _wrong = false;
  bool _checking = false;
  String? _reason;

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

    final repository = ChargingScope.maybeOf(context)?.repository;

    // Tanpa backend tidak ada rincian yang bisa dibuka; menerima kode
    // apa pun lalu menampilkan layar kosong lebih membingungkan.
    if (repository == null) {
      _reject('Rincian transaksi hanya tersedia saat terhubung ke server');
      return;
    }

    setState(() => _checking = true);

    try {
      final detail = await repository.fetchTransactionDetail(
        orderId: widget.entry.orderId,
        sessionCode: _entered,
      );
      if (!mounted) return;
      debugPrint('[FLOW] Rincian transaksi: $detail');
      Navigator.of(context).pop(detail);
    } on ApiException catch (e) {
      _reject(
        e.responseCode == ResponseCode.transactionNotFound
            ? 'Kode sesi tidak cocok dengan transaksi ini'
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
      title: 'Kode Sesi',
      subtitle: switch ((_checking, _wrong)) {
        (true, _) => 'Memeriksa kode sesi…',
        (_, true) => _reason ?? 'Kode sesi salah, coba lagi',
        _ => 'Masukkan $_length digit kode sesi transaksi ini',
      },
      titleAlign: TextAlign.center,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: _checking ? 'Memeriksa…' : 'Lihat Rincian',
            trailingAsset: null,
            onPressed: _complete && !_checking ? _verify : null,
          ),
          SecondaryButton(
            label: 'Kembali',
            leadingAsset: 'assets/icons/ic_arrow_left.svg',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SessionDigitBoxes(
            entered: _entered,
            length: _length,
            wrong: _wrong,
          ),
          const SizedBox(height: 16),
          SessionKeypad(onDigit: _press, onErase: _erase),
        ],
      ),
    );
  }
}
