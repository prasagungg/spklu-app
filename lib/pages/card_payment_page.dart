import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booking_progress.dart';
import '../data/card_reader_scope.dart';
import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../models/booking.dart';
import '../models/charging_session.dart';
import '../services/api_exception.dart';
import '../services/response_code.dart';
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
/// Begitu kartu terbaca, `POST /transaction/inquiry-billing` menanyakan
/// tagihan ordernya. Gagal di situ menahan alur: pengguna tidak boleh
/// maju ke "Pembayaran Berhasil" untuk tagihan yang tidak pernah
/// terverifikasi.
///
/// Perlu diingat **nomor kartunya tidak dibaca dari kartu**. NFC hanya
/// memberi nomor seri, bukan nomor uang elektronik, jadi yang dikirim
/// adalah [Env.cardNumber] yang tetap — lihat [CardReader]. Saldonya
/// juga belum dipotong; penagihan sungguhan menyusul setelah inquiry.
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
  /// kali. Dilepas lagi bila tagihannya gagal ditanyakan, supaya
  /// pengguna bisa mencoba menempelkan ulang.
  bool _accepted = false;

  /// Tagihan sedang ditanyakan ke backend.
  bool _inquiring = false;

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

    debugPrint('[FLOW] Kartu terbaca: $card — menanyakan tagihan');
    unawaited(_reader?.stop());
    unawaited(_settleBilling());
  }

  /// Menanyakan tagihan order ini, lalu maju bila berhasil.
  Future<void> _settleBilling() async {
    final repository = ChargingScope.maybeOf(context)?.repository;

    // Mode offline: tidak ada yang bisa ditanyakan.
    if (repository == null) {
      _proceed();
      return;
    }

    setState(() => _inquiring = true);

    try {
      final billing = await repository.inquiryBilling(
        orderId: widget.session.orderId,
      );
      if (!mounted) return;
      debugPrint('[FLOW] Tagihan: $billing');
      setState(() => _inquiring = false);

      // Di sinilah panggilan debit dipasang nanti, setelah tagihannya
      // terverifikasi dan sebelum halaman berpindah.
      _proceed();
    } on ApiException catch (e) {
      _failBilling(billingErrorMessage(e));
    } on Object catch (e) {
      _failBilling('Tagihan gagal ditanyakan: $e');
    }
  }

  void _proceed() {
    _ticker?.cancel();

    reportBookingStage(
      context,
      chargeBoxId: widget.session.chargeBox.id,
      connectorId: widget.session.connector.id,
      stage: BookingStage.paid,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PaymentSuccessPage(session: widget.session),
      ),
    );
  }

  /// Tagihannya gagal ditanyakan: kartu dibiarkan bisa ditempelkan lagi.
  Future<void> _failBilling(String message) async {
    if (!mounted) return;

    setState(() {
      _inquiring = false;
      _accepted = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

    // Sesi NFC sudah ditutup saat kartu terbaca; dibuka lagi supaya
    // tempelan berikutnya terdeteksi.
    await _reader?.start(_onCardTapped);
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
              null || CardReaderStatus.ready => WaitingPanel(
                  label: _inquiring ? 'Memeriksa Tagihan' : 'Menunggu Kartu',
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

/// Menerjemahkan kegagalan `POST /transaction/inquiry-billing` jadi
/// arahan yang bisa ditindaklanjuti pengguna.
String billingErrorMessage(ApiException e) => switch (e.responseCode) {
  // Satu-satunya field yang datang dari aplikasi di sini adalah nomor
  // kartu, jadi format yang ditolak hampir pasti soal kartunya.
  ResponseCode.invalidFieldFormat =>
    'Kartu ini tidak didukung. Pakai kartu e-Money terbitan bank yang '
        'bekerja sama (${e.message}).',
  ResponseCode.transactionNotFound || ResponseCode.transactionExpired =>
    'Pesanan tidak ditemukan atau sudah kedaluwarsa. Kembali dan ulangi '
        'pemilihan nominal.',
  ResponseCode.transactionAlreadyPaid =>
    'Pesanan ini sudah dibayar. Lanjutkan tanpa menempelkan kartu lagi.',
  ResponseCode.transactionFailed =>
    'Transaksi ditolak. Coba tempelkan kartu lagi atau pakai kartu lain.',
  ResponseCode.amountMismatch =>
    'Nominal tagihan tidak cocok. Kembali dan ulangi pemilihan nominal.',
  _ => generalErrorMessage(e),
};
