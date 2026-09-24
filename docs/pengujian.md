# Pengujian

```sh
flutter test                  # seluruh suite
flutter test test/host_test.dart
dart analyze lib test
```

Suite-nya 237 test di 28 berkas dan berjalan sekitar lima detik. Tidak
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
`test/charge_point_repository_test.dart` mengunci ejaan `connectorId`,
termasuk `chargeboxId` dengan b kecil yang hanya dipakai
`detail-chargerbox` dan `push-order`.

**Tidak memasang `ChargingScope`.** Tanpa scope, halaman berjalan dalam
mode offline: `/start` dan `/stop` dilewati dan kWh disimulasikan
lokal. Ini dipakai kalau yang diuji murni perilaku antarmuka.

**Payload daftar dibangun lewat `test/fixtures.dart`.** `listResponse()`,
`chargeBoxJson()`, dan `connectorJson()` menghasilkan bentuk `POST
/list-chargerbox` yang sesungguhnya, dengan nilai bawaan yang masuk
akal. Bentuk response berubah cukup sering, jadi mengumpulkannya di satu
berkas membuat perubahan berikutnya hanya perlu diikuti sekali.

**Mengganti `httpClientAdapter`, bukan menambah interceptor.** Interceptor
yang menjawab lewat `handler.resolve()` melompati sisa rantai, sehingga
interceptor lain — penanda tangan, perekam log — tidak pernah melihat
jawabannya. Kalau yang diuji adalah perilaku rantai interceptor itu
sendiri, ganti adapter-nya supaya seluruh rantai berjalan seperti di
produksi. Lihat `test/api_log_test.dart`.

Dio di dalam widget test juga perlu dua hal: `transformer =
SyncTransformer()` karena transformer bawaan menguraikan JSON di isolate
lain lewat `compute()`, dan panggilannya dibungkus `tester.runAsync()` —
di zona async palsu milik widget test, Future milik Dio tidak pernah
selesai.

**Membuka kembali sesi yang sedang mengisi.** `reopenChargingSession`
di `test/flow_helpers.dart` menempuh jalan yang sama seperti pengguna:
pulang dari layar kode sesi, tekan konektornya lagi, lalu masukkan
kodenya. Agar itu bisa jalan, stub harus melaporkan konektornya
berstatus `3` setelah melihat perintah start — mode offline tidak bisa
menirunya karena daftar dummy-nya statis, jadi bagian ini diuji di test
yang memakai backend tiruan.

**Menyuntik `FakeCardReader`.** Lingkungan test tidak punya NFC, jadi
alur pembayaran memerlukan pembaca palsu yang tap-nya dipicu manual.
Pasang lewat `CardReaderScope`, atau lewat parameter `cardReader` pada
`SPKLUApp`:

```dart
final reader = FakeCardReader();
await tester.pumpWidget(
  CardReaderScope(reader: reader, child: MaterialApp(home: …)),
);
…
reader.tap();            // meniru kartu ditempelkan
await settle(tester);
```

`FakeCardReader(reportedStatus: …)` dipakai untuk menguji perangkat
tanpa NFC atau NFC yang sedang dimatikan. Definisinya ada di
`test/fake_card_reader.dart` — bukan berkas `*_test.dart`, jadi tidak
ikut dijalankan sebagai suite.

## Peta berkas

### Perhitungan murni

| Berkas | Menguji |
|---|---|
| `formatters_test.dart` | Format rupiah dan kWh, termasuk energi tersalur yang dicetak tanpa pembulatan |
| `charging_session_test.dart` | Biaya pemakaian, dana kembali, breadcrumb, format tanggal |
| `host_test.dart` | Normalisasi alamat dan pengenalan jaringan privat |
| `connector_detection_test.dart` | Pemetaan angka `status` ke kelompok UI, penguraian nama/tipe konektor, dan aturan bisa-ditekan |
| `start_error_message_test.dart` | Kode error `/start` menjadi arahan yang bisa ditindaklanjuti, dan kode autentikasi tidak menyamar jadi masalah charger |

### Lapisan jaringan

| Berkas | Menguji |
|---|---|
| `charge_point_repository_test.dart` | `POST /list-chargerbox` beserta body `idSpklu`, `POST /detail-chargerbox`, perintah pengisian berkunci `orderId`, penguraian `ongoing-kwh`, dan penanganan amplop gagal |
| `api_log_test.dart` | Perekam mencatat method/path/body/status/kode, kegagalan jaringan, kapasitas riwayat, serta halaman inspektur dan penyaringnya |
| `api_client_base_url_test.dart` | Setter base URL: normalisasi, ganti berkali-kali, adapter diperbarui |
| `signature_test.dart` | Header `client-id`/`timestamp`/`signature`, format timestamp, dan tanda tangan dibandingkan dengan vektor acuan |

### Halaman dan alur

| Berkas | Menguji |
|---|---|
| `api_config_page_test.dart` | Isian awal, pratinjau alamat, uji koneksi gagal/berhasil, penyimpanan, tombol roda gigi |
| `card_payment_test.dart` | Tap kartu menanyakan tagihan lalu membayarnya dengan nominal dari inquiry, kegagalan menahan alur dan membuka lagi pembacaan kartu, pemetaan prefix kartu ke penerbit, serta keadaan NFC mati dan tanpa NFC |
| `widget_test.dart` | Render daftar charge box dan data dummy |
| `nominal_page_test.dart` | Pilihan dari `/list-kwh`, tidak ada yang terpilih di awal, perhitungan lewat `/count-kwh`, pembuatan order lewat `/transaction/push-order`, dan penanganan kode `16` |
| `booking_test.dart` | pemesanan konektor saat nozzle dipilih dan penghentian alur saat ditolak, kode sesi yang ditunjukkan sebelum nominal, `reservationId` yang dibawa `push-order` dan pembatalan, serta pelepasan konektor saat alur ditinggalkan |
| `connector_detection_poll_test.dart` | Polling `manage-sessioncode` tiap detik, tombol start mati selama menunggu, dan status tak dikenal tidak dianggap tercolok |
| `transaction_history_test.dart` | Riwayat diminta sekali lewat GET tanpa body, penguraian entri beserta asalnya, penyamaran nomor kartu, format tanggal, dan tampilan halamannya |
| `connector_sheet_test.dart` | Isi charge box diambil sekali saat sheet dibuka, status daftar ditimpa hasilnya, label tiap status, detail kosong tidak mengosongkan sheet, dan tidak ada polling |
| `charge_box_list_render_test.dart` | Dua charge box dari `/list` keduanya tampil |
| `charge_box_reload_test.dart` | `/list` dipanggil ulang tiap kembali ke daftar |
| `charge_box_refresh_test.dart` | Tarik-ke-bawah memuat ulang daftar, dan daftar tidak menyegarkan diri sendiri |
| `connector_routing_test.dart` | Tujuan tiap angka status, termasuk verifikasi sesi untuk konektor yang sudah diklaim |
| `charging_flow_test.dart` | Alur lengkap sampai layar kode sesi, pemantauan dan penghentian, tombol Home di tiap halaman |
| `charging_status_seed_test.dart` | Energi mulai dari nol lalu diisi polling `ongoing-kwh` pertama, dan sesi tanpa `orderId` tidak menanyakan apa pun |
| `final_energy_test.dart` | kWh akhir diambil dari `ongoing-kwh` terakhir, bukan saat tombol ditekan |
| `session_verification_test.dart` | Keypad dua digit, verifikasi ke `POST /manage-sessioncode`, `orderId` yang dikembalikan, dan mode offline |
| `app_wiring_test.dart` | `/start` dan `/stop` benar-benar terkirim dengan body yang benar |
| `charging_scope_test.dart` | Scope harus di atas `MaterialApp` agar terlihat rute lanjutan |

## Konvensi

**Nama test adalah kalimat yang menjelaskan perilaku**, bukan nama
method. `'kWh akhir diambil dari ongoing-kwh terakhir, bukan saat
ditekan'` memberi tahu mengapa kodenya begitu; `'testFinalEnergy'`
tidak.

**Test menjaga keputusan, bukan implementasi.** Beberapa test ada
khusus untuk mencegah bug yang pernah terjadi kembali — ejaan
`connectorId`, posisi `ChargingScope`, `pushReplacement` antara daftar
charge box dan halaman konfigurasi. Kalau salah satunya gagal, periksa dokumen yang
bersangkutan sebelum mengubah harapannya.

**Widget tanpa teks diberi `Key`.** `SessionVerificationPage.eraseKey`,
`ApiConfigPage.fieldKey`, dan `ChargeBoxPage.configKey` ada supaya test
tidak perlu menebak posisi widget di pohon.

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
