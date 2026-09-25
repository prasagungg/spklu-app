import 'package:flutter/material.dart';

import '../data/release_booking.dart';
import '../theme/app_colors.dart';
import 'primary_button.dart';

/// Tombol "Batalkan Transaksi" beserta konfirmasinya.
///
/// Dipakai di tahap-tahap yang masih boleh dibatalkan backend — selama
/// pemesanannya berstatus `HELD` atau `PENDING_PAYMENT`, yaitu sampai
/// pembayaran berhasil. Sesudah itu `POST /cancelled-connector` dijawab
/// dengan kesalahan keadaan order, jadi halaman Hubungkan Konektor ke
/// atas tidak memakainya.
class CancelTransactionButton extends StatelessWidget {
  const CancelTransactionButton({super.key, this.enabled = true});

  /// Dimatikan saat halaman sedang mengerjakan sesuatu yang tidak boleh
  /// diselingi, mis. kartu yang sedang diproses.
  final bool enabled;

  @override
  Widget build(BuildContext context) => DangerOutlineButton(
    label: 'Batalkan Transaksi',
    onPressed: enabled ? () => confirmCancelTransaction(context) : null,
  );
}

/// Menanyakan dulu, baru melepas pemesanannya.
///
/// Pembatalan tidak bisa ditarik kembali dan layar ini dipakai orang
/// yang sedang berdiri di depan charger, jadi satu ketukan tidak boleh
/// langsung membuang transaksinya.
Future<void> confirmCancelTransaction(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Ditutup lewat tombolnya, bukan gesture kembali perangkat.
    builder: (sheetContext) => PopScope(
      canPop: false,
      child: Container(
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
                'Apakah Anda yakin?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.title,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Transaksi ini akan dibatalkan dan konektornya dilepas '
                'untuk pengguna lain.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.description,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: DangerOutlineButton(
                  label: 'Batalkan',
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Tidak',
                  trailingAsset: null,
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;

  // Melepas pemesanannya sekaligus memulangkan ke halaman awal.
  await releaseBooking(context);
}
