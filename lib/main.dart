import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_route_observer.dart';
import 'config/api_config.dart';
import 'data/charge_point_repository.dart';
import 'data/charging_scope.dart';
import 'pages/api_config_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Gambar latar sengaja dibiarkan menembus ke belakang status bar dan
  // navigation bar; keterbacaan ikonnya diatur lewat AnnotatedRegion di
  // PageScaffold. Nilai awal dipasang di sini agar frame pertama tidak
  // sempat memakai gaya bawaan yang ikonnya putih.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Alamat yang terakhir dipilih operator dipasang sebelum frame
  // pertama, supaya halaman Konfigurasi Server membuka isian yang sudah
  // benar dan tidak ada request yang sempat menembak alamat lama.
  await ApiConfig.restore();

  runApp(const SPKLUApp());
}

class SPKLUApp extends StatelessWidget {
  const SPKLUApp({
    super.key,
    this.repository,
    this.home = const ApiConfigPage(),
  });

  /// Disuntik di test agar alur bisa dijalankan tanpa jaringan sungguhan.
  final ChargePointRepository? repository;

  /// Halaman pertama. Produksi selalu mulai dari Konfigurasi Server;
  /// test alur pengisian melewatinya dengan menunjuk langsung ke
  /// halaman yang sedang diuji.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    // ChargingScope harus berada DI ATAS MaterialApp. Kalau dipasang
    // sebagai `home:`, ia hanya membungkus halaman pertama — rute yang
    // dibuka lewat Navigator.push disisipkan sejajar dengan `home` di
    // bawah Navigator, bukan sebagai turunannya, sehingga
    // ChargingScope.maybeOf() mengembalikan null di halaman-halaman itu
    // dan /start maupun /stop tidak pernah terkirim.
    return ChargingScope(
      repository: repository,
      child: MaterialApp(
        title: 'SPKLU',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        // Dipakai halaman Pilih Charge Box untuk memuat ulang /list
        // setiap kali pengguna kembali ke sana.
        navigatorObservers: [appRouteObserver],
        home: home,
      ),
    );
  }
}
