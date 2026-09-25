import 'package:flutter/material.dart';

import '../data/charge_point_repository.dart';
import '../data/charging_scope.dart';
import '../data/formatters.dart';
import '../models/charge_box.dart';
import '../models/connector.dart';
import '../models/transaction_detail.dart';
import '../models/transaction_history.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_slot.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/state_view.dart';
import '../widgets/status_chip.dart';
import 'transaction_code_page.dart';
import 'transaction_detail_page.dart';

/// Satu baris riwayat beserta asalnya.
///
/// Charge box dan konektornya dicocokkan dari entri ke daftar lokasi
/// ini, supaya kartunya bisa menyebut nomor urut dan daya — dua hal
/// yang hanya ada di `POST /list-chargerbox`.
typedef HistoryRow = ({
  ChargeBox chargeBox,
  Connector connector,
  TransactionHistoryEntry entry,
});

/// Frame Figma 204:6001 — "Riwayat Transaksi", dari
/// `GET /transaction/history-transaction`.
///
/// Satu-satunya pintu masuknya tombol struk di header halaman Pilih
/// Charge Box.
///
/// **Satu panggilan untuk seluruh riwayat.** Endpoint-nya dulu sebuah
/// POST yang melayani satu konektor sekali panggil dan mewajibkan
/// `chargeBoxId` serta `connectorId`, jadi halaman ini menanyakan tiap
/// konektor lalu menggabungkan jawabannya. Sekarang GET tanpa body
/// mengembalikan semuanya, dan yang tersisa di sini hanya mengurutkan
/// terbaru lebih dulu.
class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key, this.chargeBoxes = const []});

  /// Charge box yang sedang ditampilkan halaman Pilih Charge Box.
  ///
  /// Tidak lagi menentukan apa yang ditanyakan — hanya melengkapi
  /// nomor urut, daya, dan tipe konektor pada kartunya. Riwayat charge
  /// box yang tidak ada di daftar tetap ditampilkan memakai nama dari
  /// entrinya sendiri.
  final List<ChargeBox> chargeBoxes;

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  List<HistoryRow>? _rows;
  Object? _error;

  /// Isi kotak pencarian, dicocokkan ke tanggal, nama charger, dan
  /// nominal — sesuai petunjuk di desainnya.
  String _query = '';

  ChargePointRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows != null || _error != null) return;

    _repository = ChargingScope.maybeOf(context)?.repository;
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;

    // Tanpa backend tidak ada riwayat yang bisa ditampilkan; daftar
    // kosong lebih jujur daripada data karangan.
    if (repository == null) {
      setState(() => _rows = const []);
      return;
    }

    final List<HistoryRow> rows;
    try {
      final entries = await repository.fetchTransactionHistory();
      rows = [for (final entry in entries) _rowFor(entry)];
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    if (!mounted) return;

    // Terbaru lebih dulu; entri tanpa tanggal ditaruh paling belakang.
    rows.sort((a, b) {
      final left = a.entry.createdAt;
      final right = b.entry.createdAt;
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });

    setState(() {
      _rows = rows;
      _error = null;
    });
  }

  /// Melengkapi entri dengan charge box dan konektornya.
  ///
  /// Yang dicari lebih dulu adalah charge box di daftar lokasi ini,
  /// karena hanya di situ ada nomor urut, daya, dan tipe konektornya.
  /// Yang tidak ditemukan — charge box yang sudah dilepas dari lokasi,
  /// atau entri yang tidak menyebut asalnya — dibangun dari nama di
  /// entrinya sendiri, supaya transaksinya tetap terlihat.
  HistoryRow _rowFor(TransactionHistoryEntry entry) {
    final box = widget.chargeBoxes
        .where((candidate) => candidate.id == entry.chargeBoxId)
        .firstOrNull;
    final connector = box?.connectors
        .where((candidate) => candidate.id == entry.connectorId)
        .firstOrNull;

    return (
      chargeBox:
          box ??
          ChargeBox(
            // Nomor urut hanya dimiliki charge box di daftar; nol
            // berarti kartunya tidak menampilkan nomor sama sekali.
            number: 0,
            id: entry.chargeBoxId,
            displayName: entry.chargeBoxName.isEmpty
                ? null
                : entry.chargeBoxName,
            connectors: const [],
          ),
      connector:
          connector ??
          Connector(
            id: entry.connectorId ?? 0,
            status: ConnectorStatus.unavailable,
            displayName: entry.connectorName.isEmpty
                ? null
                : entry.connectorName,
          ),
      entry: entry,
    );
  }

  /// Baris yang lolos pencarian.
  ///
  /// Penyaringannya di aplikasi, bukan di backend: seluruh riwayat
  /// lokasi ini sudah ada di tangan, dan endpoint-nya tidak menerima
  /// kata kunci apa pun.
  List<HistoryRow> _filter(List<HistoryRow> rows) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;

    return [
      for (final row in rows)
        if ([
          row.chargeBox.name,
          row.chargeBox.badge,
          row.connector.name,
          row.connector.describeWith(row.chargeBox.daya),
          formatDateTime(row.entry.createdAt),
          formatRupiah(row.entry.totalAmount),
          row.entry.maskedCard,
        ].any((field) => field.toLowerCase().contains(query)))
          row,
    ];
  }

  /// Meminta kode sesi transaksi itu, lalu membuka rinciannya.
  ///
  /// Rinciannya milik pemegang kode: daftar boleh dilihat siapa saja,
  /// isinya tidak.
  Future<void> _openDetail(HistoryRow row) async {
    final detail = await Navigator.of(context).push<TransactionDetail>(
      MaterialPageRoute<TransactionDetail>(
        builder: (_) => TransactionCodePage(entry: row.entry),
      ),
    );
    if (detail == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailPage(detail: detail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Riwayat Transaksi',
      subtitle: 'Daftar transaksi pengisian kendaraan',
      showStation: true,
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        opaque: false,
        children: [
          PrimaryButton(
            label: 'Kembali ke Halaman Awal',
            trailingAsset: 'assets/icons/ic_home_filled.svg',
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final rows = _rows;

    if (rows == null) {
      return _error == null
          ? const StateView(
              title: 'Memuat riwayat…',
              message: 'Mengambil transaksi yang pernah tercatat.',
            )
          : StateView(
              icon: Icons.error_outline_rounded,
              title: 'Gagal memuat riwayat',
              message: _error is ApiException
                  ? (_error! as ApiException).message
                  : 'Terjadi kesalahan yang tidak dikenali.',
              onRetry: _load,
              retryLabel: 'Coba Lagi',
            );
    }

    if (rows.isEmpty) {
      return StateView(
        icon: Icons.receipt_long_outlined,
        title: 'Belum ada transaksi',
        message: 'Belum ada pengisian yang tercatat di lokasi ini.',
        onRetry: _load,
      );
    }

    final shown = _filter(rows);

    // Kotak pencarian tetap ada meski hasilnya kosong — kalau ikut
    // hilang, pengguna tidak punya jalan menghapus kata kuncinya.
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: shown.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SearchField(
            onChanged: (value) => setState(() => _query = value),
          );
        }

        final row = shown[index - 1];
        return TransactionHistoryCard(
          chargeBox: row.chargeBox,
          connector: row.connector,
          entry: row.entry,
          onTap: () => _openDetail(row),
        );
      },
    );
  }
}

/// Kotak pencarian (204:6129) — putih, bergaris biru tipis, radius 12.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const AssetSlot('assets/icons/ic_search.svg', width: 20, height: 20),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: const TextStyle(fontSize: 14, color: AppColors.title),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Cari tanggal, charger atau nominal...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: AppColors.placeholder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu riwayat 204:6137 — putih, radius 16, dengan ornamen di sudut
/// kanan bawah dan tombol chevron yang membuka rinciannya.
///
/// Nomor urut dan daya datang dari daftar charge box; nama charge box
/// dan konektor bisa datang dari entrinya sendiri.
class TransactionHistoryCard extends StatelessWidget {
  const TransactionHistoryCard({
    super.key,
    required this.chargeBox,
    required this.connector,
    required this.entry,
    this.onTap,
  });

  final ChargeBox chargeBox;
  final Connector connector;
  final TransactionHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              const Positioned(
                right: 0,
                bottom: 0,
                child: AssetSlot(
                  'assets/images/history_card_corner.svg',
                  width: 108,
                  height: 46,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // Nomor urutnya milik daftar charge box;
                            // entri dari charge box yang tidak ada di
                            // situ cukup menyebut namanya.
                            chargeBox.number > 0
                                ? '${chargeBox.badge} - ${chargeBox.name}'
                                : chargeBox.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.cardTitle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            // "Gun 1 - CCS2 - 200 kW DC"; dayanya milik
                            // charge box, bukan konektornya.
                            '${connector.name} - '
                            '${connector.describeWith(chargeBox.daya)}',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.cardCaption.copyWith(
                              color: AppColors.icon,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.borderAlt,
                          ),
                          const SizedBox(height: 8),
                          _IconDetail(
                            asset: 'assets/icons/ic_clock.svg',
                            text: formatDateTime(entry.createdAt),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _IconDetail(
                                asset: 'assets/icons/ic_coins.svg',
                                text: formatRupiah(entry.totalAmount),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                child: _IconDetail(
                                  asset: 'assets/icons/ic_wallet.svg',
                                  text: entry.maskedCard,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const CircleIconButton(
                      asset: 'assets/icons/ic_chevron.svg',
                      size: 32,
                      iconSize: 20,
                      // Seluruh kartunya yang menerima tekanan; tombol
                      // ini penanda arah, bukan sasaran tersendiri.
                      onTap: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ikon 16x16 dengan teks di sebelahnya, jarak 4 (189:766).
class _IconDetail extends StatelessWidget {
  const _IconDetail({required this.asset, required this.text});

  final String asset;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AssetSlot(asset, width: 16, height: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.cardCaption.copyWith(color: AppColors.description),
          ),
        ),
      ],
    );
  }
}
