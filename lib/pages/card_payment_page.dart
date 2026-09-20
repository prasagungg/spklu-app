import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booking_progress.dart';
import '../data/card_reader_scope.dart';
import '../data/formatters.dart';
import '../models/booking.dart';
import '../models/charging_session.dart';
import '../services/card_reader.dart';
import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';
import 'payment_success_page.dart';

/// Frame Figma 73:2776 — "Pembayaran Kartu".
///
/// Halaman ini menunggu kartu e-Money ditempelkan ke pembaca NFC. Tidak
/// ada tombol untuk memajukannya: yang memajukan alur adalah tap kartu
/// itu sendiri, persis seperti di mesin pembayaran sungguhan.
///
/// Perlu diingat tap di sini hanya *memicu* langkah berikutnya. Saldo
/// kartu tidak dibaca dan tidak dipotong — lihat [CardReader] untuk
/// sebabnya, dan di mana panggilan debit sungguhan nanti dipasang.
class CardPaymentPage extends StatefulWidget {
  const CardPaymentPage({super.key, required this.session});

  final ChargingSession session;

  @override
  State<CardPaymentPage> createState() => _CardPaymentPageState();
}

class _CardPaymentPageState extends State<CardPaymentPage> {
  static const _limit = Duration(minutes: 10);

  Timer? _ticker;
  Duration _remaining = _limit;

  CardReader? _reader;
  CardReaderStatus? _status;

  /// Kartu bisa terbaca berkali-kali selama masih menempel; tap pertama
  /// yang menang dan sisanya diabaikan agar halaman tidak didorong dua
  /// kali.
  bool _accepted = false;

  @override
  void initState() {
    super.initState();

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reader != null) return;

    _reader = CardReaderScope.maybeOf(context) ?? NfcCardReader();
    unawaited(_beginWaiting());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_reader?.stop());
    super.dispose();
  }

  /// Memeriksa kesiapan pembaca, lalu mulai menunggu kartu.
  Future<void> _beginWaiting() async {
    final reader = _reader!;
    final status = await reader.status();
    if (!mounted) return;

    setState(() => _status = status);
    if (status != CardReaderStatus.ready) {
      debugPrint('[FLOW] Pembaca kartu tidak siap: ${status.name}');
      return;
    }

    await reader.start(_onCardTapped);
  }

  /// Memeriksa ulang setelah pengguna menyalakan NFC dari pengaturan.
  Future<void> _recheck() async {
    setState(() => _status = null);
    await _beginWaiting();
  }

  /// Kartu ditempelkan — inilah yang menggantikan tombol bayar.
  ///
  /// Dipanggil dari callback platform, jadi bisa tiba saat halaman
  /// sudah ditinggalkan.
  void _onCardTapped(TappedCard card) {
    if (_accepted || !mounted) return;
    _accepted = true;

    debugPrint('[FLOW] Kartu terbaca: $card — menuju Pembayaran Berhasil');

    unawaited(_reader?.stop());
    _ticker?.cancel();

    reportBookingStage(
      context,
      chargeBoxId: widget.session.chargeBox.id,
      connectorId: widget.session.connector.id,
      stage: BookingStage.paid,
    );

    // Di sinilah panggilan debit ke backend pembayaran dipasang nanti,
    // sebelum halaman berpindah.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PaymentSuccessPage(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _status == null || _status == CardReaderStatus.ready;

    return PageScaffold(
      title: 'Pembayaran',
      subtitle: ready
          ? 'Tempelkan kartu e-Money Anda pada reader.'
          : 'Pembaca kartu belum bisa dipakai.',
      backgroundColor: AppColors.pageBackgroundPlain,
      // Halaman ini memakai ilustrasi reader sebagai latar penuh.
      backgroundAsset: 'assets/images/bg_payment.png',
      backgroundOpacity: 1,
      headerExtra: CountdownPill(remaining: _remaining),
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          // Tidak ada tombol bayar: kartu yang ditempelkan sendiri yang
          // memajukan alur.
          if (!ready)
            PrimaryButton(
              label: 'Periksa Lagi',
              trailingAsset: 'assets/icons/ic_refresh.svg',
              onPressed: _recheck,
            ),
          SecondaryButton(
            label: 'Bantuan',
            trailingAsset: 'assets/icons/ic_support.svg',
            onPressed: () => showHelpSheet(context),
          ),
        ],
      ),
      child: Column(
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: switch (_status) {
              // Kesiapan masih diperiksa — tampilannya sama dengan
              // menunggu kartu, jadi layar tidak berkedip.
              null || CardReaderStatus.ready => const WaitingPanel(
                  label: 'Menunggu Kartu',
                  soft: true,
                ),
              CardReaderStatus.disabled => const _ReaderNotice(
                  text: 'NFC sedang mati. Nyalakan NFC di pengaturan '
                      'perangkat, lalu tekan Periksa Lagi.',
                ),
              CardReaderStatus.unsupported => const _ReaderNotice(
                  text: 'Perangkat ini tidak punya pembaca NFC, jadi kartu '
                      'e-Money tidak bisa dibaca. Hubungi petugas.',
                ),
            },
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SessionInfoRow(
              // Halaman pembayaran hanya dicapai dari alur pembelian.
              nominalLabel: formatRupiah(widget.session.price!.rpTotal),
              sessionCode: widget.session.sessionCode,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel kaca berisi keterangan kenapa pembaca kartu belum bisa
/// dipakai — mengambil bentuk [WaitingPanel] tanpa spinner, karena di
/// sini memang tidak ada yang sedang ditunggu.
class _ReaderNotice extends StatelessWidget {
  const _ReaderNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      soft: true,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.contactless_outlined,
            size: 22,
            color: AppColors.unavailableFg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.title,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frame Figma 73:2935 — "Bantuan", ditampilkan sebagai bottom sheet.
Future<void> showHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Butuh Bantuan?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.title,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hubungi petugas di lokasi atau call center PLN 123 bila '
              'pengisian tidak berjalan sebagaimana mestinya.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.description,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Tutup',
                trailingAsset: null,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
