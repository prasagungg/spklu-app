import 'package:flutter/material.dart';

import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../models/charging_detail.dart';
import '../models/charging_session.dart';
import '../models/transaction_detail.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/price_breakdown.dart';
import '../widgets/primary_button.dart';
import '../widgets/session_widgets.dart';

/// Frame Figma 73:5171 — "Pengisian Selesai".
///
/// Angkanya datang dari `POST /transaction/charging/detail`: kWh yang
/// dipesan, tersalur, dan tersisa, lalu nominal yang dibayar, terpakai,
/// dan dikembalikan. Aplikasi tidak menghitungnya sendiri — hitungan
/// lokal tidak pernah bisa dijamin sama dengan pembukuan backend.
///
/// Keduanya dibaca sebagai pasangan yang sama: pesan → pakai → sisa,
/// sekali dalam kWh dan sekali dalam rupiah, di bawah nomor order,
/// penerbit, dan nomor kartu yang menjadi pegangan pengguna bila ada
/// yang perlu ditanyakan ke petugas.
///
/// Dua endpoint ditanya sekaligus, karena tidak ada satu pun yang
/// membawa semuanya:
///
/// | | `charging/detail` | `detail-history-transaction` |
/// |---|---|---|
/// | Angka kWh dan rupiah | ya | ya |
/// | Nomor kartu | — | ya, sudah disamarkan backend |
/// | Penerbit kartu | — | ya |
///
/// Angkanya **hanya** diambil dari `charging/detail`, tidak pernah dari
/// riwayat. Dua alasannya:
///
/// - `detail-history-transaction` mengirim `sisaKwh` dan `rpSisa`
///   sebagai null pada transaksi yang tidak sampai selesai, dan null di
///   sana terurai menjadi nol — tidak bisa dibedakan dari nol yang
///   sungguhan.
/// - Ketika `charging/detail` tidak menjawab, yang tersisa adalah
///   bacaan terakhir layar pemantauan, dan itu angka yang benar-benar
///   dilihat pengguna beberapa detik lalu.
///
/// Riwayat dipakai untuk satu hal saja: identitas kartunya, satu-satunya
/// yang punya.
///
/// Rinciannya ditahan sampai **keduanya** selesai, baru ditampilkan
/// sekaligus. Menampilkannya lebih awal membuat barisnya muncul satu per
/// satu begitu jawabannya berdatangan — terbaca seperti aplikasi yang
/// tersendat, bukan seperti layar yang sedang memuat.
///
/// Keduanya boleh gagal. Yang gagal hanya meninggalkan barisnya kosong
/// atau jatuh ke angka layar sebelumnya; layar penutup tidak menahan
/// pengguna yang sudah selesai. Tombol pulang tetap ada selama menunggu,
/// jadi jaringan yang lambat tidak pernah mengurung siapa pun.
///
/// Selama rinciannya belum datang, dan bila panggilannya gagal atau
/// sesinya tidak punya order (mode offline), yang ditampilkan adalah
/// angka yang sudah dipegang layar sebelumnya.
class ChargingFinishedPage extends StatefulWidget {
  const ChargingFinishedPage({
    super.key,
    required this.session,
    required this.energyKwh,
  });

  final ChargingSession session;
  final double energyKwh;

  @override
  State<ChargingFinishedPage> createState() => _ChargingFinishedPageState();
}

class _ChargingFinishedPageState extends State<ChargingFinishedPage> {
  ChargingDetail? _detail;
  TransactionDetail? _transaction;
  bool _asked = false;

  /// Kedua permintaannya belum selesai. Selama ini rinciannya ditahan
  /// supaya barisnya tidak muncul satu per satu.
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;

    final repository = ChargingScope.maybeOf(context)?.repository;
    final session = widget.session;
    if (repository == null || session.orderId.isEmpty) {
      // Tidak ada yang bisa ditanya — mode offline, atau sesi tanpa
      // order. Angka layar sebelumnya sudah lengkap, jadi tidak ada
      // gunanya menahan apa pun.
      _loading = false;
      return;
    }

    () async {
      // Berjalan berdampingan, bukan berurutan: keduanya saling berdiri
      // sendiri, dan yang satu gagal tidak boleh menahan yang lain.
      // Keduanya menelan errornya masing-masing, jadi Future.wait di
      // sini tidak akan pernah gagal — ia hanya menunggu.
      await Future.wait([
        _loadChargingDetail(repository, session.orderId),
        if (session.sessionCode.isNotEmpty)
          _loadTransaction(repository, session.orderId, session.sessionCode),
      ]);
      if (!mounted) return;

      setState(() => _loading = false);
    }();
  }

  Future<void> _loadChargingDetail(
    ChargePointRepository repository,
    String orderId,
  ) async {
    try {
      final detail = await repository.fetchChargingDetail(orderId: orderId);
      if (!mounted) return;
      debugPrint('[FLOW] Rincian akhir: $detail');

      // Amplop tanpa `data` terurai menjadi nol semua. Memakainya akan
      // menghapus angka yang sudah benar di layar, jadi hanya rincian
      // yang benar-benar berisi yang dipakai.
      // Dicatat tanpa setState: yang menggambar ulang layar adalah satu
      // setState setelah kedua permintaannya selesai.
      if (detail.orderId.isNotEmpty) _detail = detail;
    } on Object catch (e) {
      // Angka dari layar sebelumnya tetap ditampilkan; memunculkan error
      // di layar penutup hanya menahan pengguna yang sudah selesai.
      debugPrint('[FLOW] Rincian akhir gagal diambil: $e');
    }
  }

  /// Nomor dan penerbit kartunya hanya ada di sini.
  Future<void> _loadTransaction(
    ChargePointRepository repository,
    String orderId,
    String sessionCode,
  ) async {
    try {
      final transaction = await repository.fetchTransactionDetail(
        orderId: orderId,
        sessionCode: sessionCode,
      );
      if (!mounted) return;
      debugPrint('[FLOW] Riwayat transaksi: $transaction');

      if (transaction.orderId.isNotEmpty) _transaction = transaction;
    } on Object catch (e) {
      // Barisnya tinggal tidak muncul. Sesi yang kartunya ditempelkan di
      // unit ini masih punya cadangan dari tagihannya sendiri.
      debugPrint('[FLOW] Riwayat transaksi gagal diambil: $e');
    }
  }

  /// Satu-satunya tombol halaman ini, dan ia ada selagi menunggu maupun
  /// sesudahnya: jaringan yang lambat tidak boleh mengurung siapa pun di
  /// layar tunggu.
  Widget _homeBar() => BottomActionBar(
    opaque: false,
    children: [
      PrimaryButton(
        label: 'Kembali ke Halaman Awal',
        trailingAsset: 'assets/icons/ic_home_filled.svg',
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    ],
  );

  /// Layar tunggu selagi kedua rinciannya diambil.
  ///
  /// Gambar dan judulnya sama persis dengan layar akhirnya, jadi yang
  /// berubah saat jawabannya tiba hanya panel tunggu yang berganti jadi
  /// kartu rincian — bukan seluruh halaman yang tersusun ulang.
  Widget _waiting() => PageScaffold(
    backgroundColor: AppColors.pageBackgroundPlain,
    bottomBar: _homeBar(),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: const [
        Center(
          child: AssetSlot(
            'assets/images/finished_check.png',
            width: 180,
            height: 180,
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Pengisian Selesai',
          textAlign: TextAlign.center,
          style: AppTheme.pageTitle,
        ),
        SizedBox(height: 16),
        WaitingPanel(label: 'Menyiapkan rincian…'),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _waiting();

    final session = widget.session;
    final detail = _detail;
    final transaction = _transaction;

    String firstFilled(List<String> values) =>
        values.firstWhere((value) => value.isNotEmpty, orElse: () => '');

    // Energi dari backend bila ada; kalau tidak, angka terakhir yang
    // dilihat layar pemantauan.
    final energyKwh = detail?.usedKwh ?? widget.energyKwh;

    // Tanpa rincian backend, yang dipesan dibaca dari pembelian yang
    // dipegang sesi ini. Sesi yang dilanjutkan tidak membawanya, dan
    // kedua baris kWh-nya ikut disembunyikan.
    final ordered = detail?.orderedKwh ?? session.price?.kwh;

    // Sisanya lebih baik diambil apa adanya dari backend. Selisih yang
    // dihitung di sini hanya cadangan, dan dijaga tidak negatif: charger
    // kadang menyalurkan sedikit lebih banyak dari yang dipesan.
    //
    // Dibulatkan ke tiga desimal — seperempat Wh, lebih halus daripada
    // apa pun yang dilaporkan charger. [formatEnergy] sengaja
    // menampilkan angka apa adanya supaya bacaan backend tidak
    // terdistorsi, jadi 10 - 6,4 yang menghasilkan 3,5999999999999996
    // akan tampil utuh kalau tidak dirapikan di sini.
    final remaining =
        detail?.remainingKwh ??
        (ordered == null
            ? null
            : double.parse(
                (ordered - energyKwh).clamp(0.0, ordered).toStringAsFixed(3),
              ));

    // Nomor order dipakai petugas untuk menelusuri transaksinya.
    final orderId = firstFilled([
      transaction?.orderId ?? '',
      detail?.orderId ?? '',
      session.orderId,
    ]);

    // Riwayat menyamarkannya sendiri ("012••••••••••345"), jadi dipakai
    // apa adanya. Cadangannya tagihan yang dipegang sesi ini — hanya ada
    // bila kartunya memang ditempelkan di unit ini, dan disamarkan
    // aplikasi. Layar kios berdiri di tempat umum; nomor utuh tidak
    // pernah ditampilkan lewat kedua jalan itu.
    final card = firstFilled([
      transaction?.cardNumber ?? '',
      session.billing?.maskedCard ?? '',
    ]);

    // Hanya riwayat yang tahu penerbitnya.
    final issuer = transaction?.pspId ?? '';

    final paid = detail?.paidAmount ?? session.paidAmount;
    final usage = detail?.usageAmount ?? session.usageCostFor(energyKwh);
    final refund = detail?.refundAmount ?? session.refundFor(energyKwh);

    // Sesi yang dilanjutkan tanpa data pembelian tetap menyembunyikan
    // baris rupiahnya — kecuali backend yang menyebutkan angkanya.
    final hasAmounts = detail != null || session.hasPurchase;

    return PageScaffold(
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: _homeBar(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Center(
            child: AssetSlot(
              'assets/images/finished_check.png',
              width: 180,
              height: 180,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pengisian Selesai',
            textAlign: TextAlign.center,
            style: AppTheme.pageTitle,
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.borderAlt),
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppColors.cardShadow,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (orderId.isNotEmpty) ...[
                  DetailRow(label: 'No Order', value: orderId, muted: true),
                  const SizedBox(height: 16),
                ],
                if (issuer.isNotEmpty) ...[
                  DetailRow(
                    label: 'Penerbit Kartu',
                    value: issuer,
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                ],
                if (card.isNotEmpty) ...[
                  DetailRow(label: 'Nomor Kartu', value: card, muted: true),
                  const SizedBox(height: 16),
                ],
                if (ordered != null) ...[
                  DetailRow(
                    label: 'kWh Pesan',
                    value: formatEnergy(ordered),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                ],
                DetailRow(
                  label: 'Energi Tersalur',
                  value: formatEnergy(energyKwh),
                  muted: true,
                ),
                if (remaining != null) ...[
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Sisa kWh',
                    value: formatEnergy(remaining),
                    muted: true,
                  ),
                ],
                // Sesi yang dilanjutkan tidak membawa data pembelian,
                // jadi baris pembayarannya dilewati.
                if (hasAmounts) ...[
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Pembayaran Awal',
                    value: formatRupiah(paid ?? 0),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Total Pemakaian',
                    value: formatRupiah(usage ?? 0),
                    muted: true,
                  ),
                  const SizedBox(height: 16),
                  DetailRow(
                    label: 'Sisa Pembayaran',
                    value: formatRupiah(refund ?? 0),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const NoticeBar(
            text: 'Lepas dan kembalikan konektor ke tempatnya',
            asset: 'assets/icons/ic_connector.svg',
          ),
        ],
      ),
    );
  }
}
