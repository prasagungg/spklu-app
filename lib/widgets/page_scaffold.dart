import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/env.dart';
import '../pages/api_log_page.dart';
import '../pages/settings_page.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'asset_slot.dart';
import 'status_chip.dart';

/// Kerangka halaman sesuai Figma: background full-bleed 50% opacity,
/// mobile header berisi logo, lalu blok judul + subjudul opsional.
class PageScaffold extends StatelessWidget {
  /// Area logo di header, dipakai test untuk memicu tekan lama yang
  /// membuka inspektur jaringan.
  static const logKey = Key('buka-log-api');

  const PageScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.titleAlign = TextAlign.start,
    this.titleTrailing,
    this.headerAction,
    this.headerExtra,
    this.isHome = false,
    this.showStation = false,
    this.bottomBar,
    this.backgroundColor = AppColors.pageBackground,
    this.backgroundAsset = 'assets/images/bg_page.png',
    this.backgroundOpacity = 0.5,
  });

  final Widget child;

  /// Judul besar. Null berarti halaman menyusun headernya sendiri.
  final String? title;
  final String? subtitle;
  final TextAlign titleAlign;

  /// Elemen di ujung kanan baris judul, mis. pil hitung mundur kecil
  /// (204:4690). Berbeda dari [headerExtra], yang menempati barisnya
  /// sendiri di bawah subjudul.
  final Widget? titleTrailing;

  /// Mengganti tombol bawaan di ujung kanan mobile header.
  final Widget? headerAction;

  /// Elemen tambahan tepat di bawah subjudul, mis. pil hitung mundur.
  final Widget? headerExtra;

  /// Halaman awal itu sendiri — tidak perlu tombol Home.
  final bool isHome;

  /// Ilustrasi charging station yang menimpa pojok kanan atas.
  final bool showStation;

  final Widget? bottomBar;
  final Color backgroundColor;
  final String backgroundAsset;
  final double backgroundOpacity;

  /// Background halaman terang, jadi ikon status bar harus gelap agar
  /// tetap terbaca. Status bar dibuat transparan supaya gambar latar
  /// tetap menembus ke atas (edge-to-edge) tanpa menutupi ikonnya.
  static const SystemUiOverlayStyle _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android: kecerahan ikon. iOS: kecerahan latar di baliknya.
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    // Tinggi status bar / notch. Dipakai untuk menggeser ilustrasi
    // station agar tidak menindih jam dan ikon baterai.
    final topInset = MediaQuery.viewPaddingOf(context).top;
    // headerExtra ikut dihitung: ada halaman yang hanya memakai pil
    // hitung mundur, tanpa judul apa pun.
    final hasTitleBlock =
        title != null || subtitle != null || headerExtra != null;

    // Tombol dan gesture kembali bawaan perangkat dimatikan di semua
    // halaman: unit ini kios, dan alurnya punya urutan yang harus
    // dijaga — konektor yang sudah dikunci perlu dilepas, perintah stop
    // perlu kode sesi. Satu-satunya jalan berpindah adalah tombol di
    // dalam aplikasi, yang tahu apa yang harus dibereskan lebih dulu.
    //
    // `canPop: false` hanya menahan pop dari sistem; `Navigator.pop`
    // yang dipanggil tombol aplikasi tetap jalan seperti biasa.
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyle,
        child: Scaffold(
          backgroundColor: backgroundColor,
          body: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: backgroundOpacity,
                  child: AssetSlot(backgroundAsset, fit: BoxFit.cover),
                ),
              ),
              // Diperbesar dari 127dp desain. Offset kanan dinaikkan agar
              // tepi kiri ilustrasi tetap bebas dari subjudul — station
              // tumbuh ke arah luar layar, bukan ke arah teks.
              if (showStation)
                Positioned(
                  top: topInset - 4,
                  right: -48,
                  child: const AssetSlot(
                    'assets/images/station.png',
                    width: 176,
                    height: 176,
                  ),
                ),
              // bottom: false — bilah tombol mengurus inset bawahnya sendiri
              // supaya background putihnya menembus sampai tepi layar.
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MobileHeader(
                      action:
                          headerAction ?? (isHome ? null : const HomeButton()),
                    ),
                    if (hasTitleBlock)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: titleAlign == TextAlign.center
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.start,
                          children: [
                            if (title != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title!,
                                      textAlign: titleAlign,
                                      style: AppTheme.pageTitle,
                                    ),
                                  ),
                                  ?titleTrailing,
                                ],
                              ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              SizedBox(
                                width: double.infinity,
                                child: Text(
                                  subtitle!,
                                  textAlign: titleAlign,
                                  style: AppTheme.pageSubtitle,
                                ),
                              ),
                            ],
                            if (headerExtra != null) ...[
                              const SizedBox(height: 8),
                              headerExtra!,
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Tanpa bilah tombol, isi halaman sendiri yang harus
                    // menghormati inset bawah.
                    Expanded(
                      child: bottomBar == null
                          ? SafeArea(top: false, child: child)
                          : child,
                    ),
                    ?bottomBar,
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

/// Mobile Header (70:1904): tinggi 64, padding horizontal 16.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [const _LogoGestures(), const Spacer(), ?action]),
      ),
    );
  }
}

/// Logo SPKLU Hybrid.
///
/// PNG ekspor Figma punya area kosong lebar di sekelilingnya; di Figma
/// (node 70:1906) gambar itu dirender 109,04% × 171,97% dari jendela
/// 151×32 lalu digeser −6,28% / −37,29% sehingga yang tampak hanya
/// bagian berisinya. Crop yang sama direplikasi di sini — memakai
/// BoxFit.contain apa adanya membuat logo terlihat jauh lebih kecil.
class LogoImage extends StatelessWidget {
  const LogoImage({super.key, this.height = 44});

  /// Tinggi jendela logo. Lebar mengikuti rasio 151:32 dari Figma.
  final double height;

  // Jendela logo pada desain.
  static const double _frameWidth = 151;
  static const double _frameHeight = 32;

  // Transform gambar di dalam jendela tersebut.
  static const double _imageWidthRatio = 1.0904;
  static const double _imageHeightRatio = 1.7197;
  static const double _imageLeftRatio = -0.0628;
  static const double _imageTopRatio = -0.3729;

  @override
  Widget build(BuildContext context) {
    final scale = height / _frameHeight;
    final width = _frameWidth * scale;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: _imageLeftRatio * width,
              top: _imageTopRatio * height,
              width: _imageWidthRatio * width,
              height: _imageHeightRatio * height,
              child: const AssetSlot(
                'assets/images/logo_spklu.png',
                fit: BoxFit.fill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol Home bundar di ujung kanan mobile header (73:3759).
///
/// Dipasang otomatis oleh [PageScaffold] di semua halaman kecuali yang
/// menandai dirinya `isHome`, sehingga tidak ada halaman yang lupa
/// menyediakan jalan pulang.
class HomeButton extends StatelessWidget {
  const HomeButton({super.key, this.onTap});

  /// Bawaannya membuang seluruh tumpukan rute sampai halaman awal.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CircleIconButton(
      asset: 'assets/icons/ic_home.svg',
      onTap: onTap ?? () => Navigator.of(context).popUntil((r) => r.isFirst),
    );
  }
}

/// Logo di header, sekaligus dua pintu petugas yang sengaja tidak
/// diberi penanda apa pun: pengguna tidak akan menemukannya secara tak
/// sengaja, petugas cukup diberi tahu caranya.
///
/// - **Tekan lama** — inspektur jaringan (hanya bila panel debug menyala).
/// - **Ketuk lima kali** — halaman Pengaturan, setelah password benar.
class _LogoGestures extends StatefulWidget {
  const _LogoGestures();

  @override
  State<_LogoGestures> createState() => _LogoGesturesState();
}

class _LogoGesturesState extends State<_LogoGestures> {
  /// Ketukan yang berjeda lebih lama dari ini dianggap ketukan biasa,
  /// bukan bagian dari rangkaian — supaya sentuhan tak sengaja di sela
  /// pemakaian tidak menumpuk menjadi lima.
  static const _window = Duration(seconds: 2);
  static const _tapsNeeded = 5;

  int _taps = 0;

  /// Melupakan hitungan bila ketukan berikutnya tidak datang tepat
  /// waktu. Dipakai timer, bukan selisih jam dinding, supaya jendela
  /// waktunya bisa diuji.
  Timer? _forget;

  /// Dialog password sedang terbuka; ketukan berikutnya diabaikan
  /// supaya tidak menumpuk dua dialog.
  bool _opening = false;

  @override
  void dispose() {
    _forget?.cancel();
    super.dispose();
  }

  Future<void> _onTap() async {
    _forget?.cancel();
    _taps++;

    if (_taps < _tapsNeeded) {
      _forget = Timer(_window, () => _taps = 0);
      return;
    }

    _taps = 0;
    if (_opening) return;

    _opening = true;
    try {
      await openSettings(context);
    } finally {
      if (mounted) _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: PageScaffold.logKey,
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      onLongPress: Env.enableDebugPanel ? () => ApiLogPage.open(context) : null,
      child: const LogoImage(height: 44),
    );
  }
}
