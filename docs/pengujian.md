# Pengujian

```sh
flutter test                  # seluruh suite
flutter test test/host_test.dart
dart analyze lib test
```

Suite-nya 106 test di 21 berkas dan berjalan sekitar lima detik. Tidak
ada yang menyentuh jaringan.

## Cara test menghindari jaringan

Ada dua teknik, dipilih sesuai yang sedang diuji.

**Menyuntik Dio dengan interceptor.** Interceptor yang menjawab sendiri
lewat `handler.resolve()` membuat request tidak pernah keluar. Ini
dipakai kalau yang diuji adalah apa yang dikirim aplikasi atau bagaimana
response diurai.

```dart
class _Stub extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: const {'responseCode': '00', 'data': {}},
    ));
  }
}

final repo = ChargePointRepository(
  client: ApiClient.withDio(Dio()..interceptors.add(_Stub())),
);
```

Menyimpan `options` yang lewat memungkinkan test memeriksa path, query,
dan body yang benar-benar dikirim — itulah cara
`test/progress_test.dart` mengunci ejaan `connectorId`.

**Tidak memasang `ChargingScope`.** Tanpa scope, halaman berjalan dalam
mode offline: `/start` dan `/stop` dilewati dan kWh disimulasikan
lokal. Ini dipakai kalau yang diuji murni perilaku antarmuka.

## Peta berkas

### Perhitungan murni

| Berkas | Menguji |
|---|---|
| `formatters_test.dart` | Format rupiah dan kWh, termasuk aturan tiga desimal di bawah 1 kWh |
| `charging_session_test.dart` | Biaya pemakaian, dana kembali, breadcrumb, format tanggal |
| `host_test.dart` | Normalisasi alamat dan pengenalan jaringan privat |
| `session_info_test.dart` | Parsing `session` dan estimasi sisa waktu |
| `connector_detection_test.dart` | Pemetaan status OCPP ke kelompok UI dan aturan bisa-ditekan |
| `start_error_message_test.dart` | Kode error `/start` menjadi arahan yang bisa ditindaklanjuti |

### Lapisan jaringan

| Berkas | Menguji |
|---|---|
| `charge_point_repository_test.dart` | Pemetaan `/list`, daftar kosong, `data` null, `responseCode` bukan `00` |
| `progress_test.dart` | Query `/progress`, konversi Wh ke kWh, sesi selesai dengan `powerW` null |
| `api_client_base_url_test.dart` | Setter base URL: normalisasi, ganti berkali-kali, adapter diperbarui |

### Halaman dan alur

| Berkas | Menguji |
|---|---|
| `api_config_page_test.dart` | Isian awal, pratinjau alamat, uji koneksi gagal/berhasil, penyimpanan, tombol roda gigi |
| `widget_test.dart` | Render daftar charge box dan data dummy |
| `charge_box_list_render_test.dart` | Dua charge box dari `/list` keduanya tampil |
| `charge_box_reload_test.dart` | `/list` dipanggil ulang tiap kembali ke daftar |
| `charge_box_auto_refresh_test.dart` | Charger yang tersambung atau terputus muncul dan hilang sendiri |
| `connector_routing_test.dart` | Percabangan tujuan menurut status konektor |
| `charging_flow_test.dart` | Alur lengkap, pembatalan stop, tombol Home di tiap halaman |
| `charging_status_seed_test.dart` | Energi awal diambil dari sesi yang dibawa `/list` |
| `final_energy_test.dart` | kWh akhir diambil dari `/progress` terakhir, bukan saat tombol ditekan |
| `session_verification_test.dart` | Keypad dua digit, kode salah, tombol hapus |
| `app_wiring_test.dart` | `/start` dan `/stop` benar-benar terkirim dengan body yang benar |
| `charging_scope_test.dart` | Scope harus di atas `MaterialApp` agar terlihat rute lanjutan |

## Konvensi

**Nama test adalah kalimat yang menjelaskan perilaku**, bukan nama
method. `'kWh akhir diambil dari /progress terakhir, bukan saat
ditekan'` memberi tahu mengapa kodenya begitu; `'testFinalEnergy'`
tidak.

**Test menjaga keputusan, bukan implementasi.** Beberapa test ada
khusus untuk mencegah bug yang pernah terjadi kembali — ejaan
`connectorId`, posisi `ChargingScope`, `pushReplacement` di halaman
konfigurasi. Kalau salah satunya gagal, periksa dokumen yang
bersangkutan sebelum mengubah harapannya.

**Widget tanpa teks diberi `Key`.** `SessionVerificationPage.eraseKey`,
`ApiConfigPage.fieldKey`, dan `ChargeBoxPage.configKey` ada supaya test
tidak perlu menebak posisi widget di pohon.

**Memulai dari halaman tertentu.** `SPKLUApp` menerima parameter `home`.
Produksi selalu mulai dari Konfigurasi Server; test alur pengisian
menunjuk langsung ke halaman yang sedang diuji:

```dart
await tester.pumpWidget(
  SPKLUApp(repository: repo, home: const ChargeBoxPage()),
);
```

**Timer dan polling.** Halaman yang mem-polling memakai timer berkala,
jadi `pumpAndSettle()` saja tidak cukup untuk memajukan waktu. Pakai
`tester.pump(const Duration(seconds: 2))` sesuai jeda yang relevan dari
`Env`.

**`shared_preferences` di test.** Panggil
`SharedPreferences.setMockInitialValues({})` di `setUp`. Tanpa itu
plugin-nya tidak ada, dan meski `ApiConfig` menangani kegagalan dengan
diam, nilai yang disimpan tidak bisa diperiksa.

**Alamat aktif itu global.** `ApiConfig` menyimpan alamat pada state
statis. Test yang menyentuhnya harus mengembalikan ke bawaan di `setUp`:

```dart
setUp(() {
  SharedPreferences.setMockInitialValues({});
  ApiConfig.apply(Env.apiBaseUrl);
});
```
