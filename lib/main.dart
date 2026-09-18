import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_route_observer.dart';
import 'data/charge_point_repository.dart';
import 'data/charging_scope.dart';
import 'pages/charge_box_page.dart';
import 'theme/app_theme.dart';

void main() {
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

  runApp(const SPKLUApp());
}

class SPKLUApp extends StatelessWidget {
  const SPKLUApp({super.key, this.repository});

  /// Disuntik di test agar alur bisa dijalankan tanpa jaringan sungguhan.
  final ChargePointRepository? repository;

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
        home: const ChargeBoxPage(),
      ),
    );
  }
}
