# kossotrik

Aplikasi kontrol SPKLU: pilih charge box, bayar, lalu pantau pengisian
kendaraan listrik sampai selesai.

Aplikasi ini berbicara ke sebuah **edge controller OCPP 1.6** lewat REST.
Controller itu yang meneruskan perintah ke charger; aplikasi hanya
meminta dan menampilkan. Target platformnya Android.

| | |
|---|---|
| Framework | Flutter (Dart SDK `^3.11.5`) |
| Dependensi | `dio`, `flutter_svg`, `shared_preferences`, `nfc_manager`, `crypto` |
| Bahasa antarmuka | Indonesia |
| Sumber desain | Figma "SPKLU Offline Mode" |

## Jalankan

```sh
flutter pub get
flutter run
```

Alamat backend **tidak perlu** ditentukan saat build. Aplikasi langsung
membuka daftar charge box memakai alamat yang tersimpan. Untuk
menggantinya, tekan ikon roda gigi di header halaman itu — halaman
**Konfigurasi Server** terbuka di sana. Cukup mengetik IP —
`192.168.1.10:8080` otomatis menjadi `http://192.168.1.10:8080`.

Untuk mengganti alamat bawaan saat belum pernah ada yang disimpan:

```sh
flutter run --dart-define=SPKLU_API_BASE_URL=10.0.2.2:8080
```

Daftar lengkap `--dart-define` ada di [docs/konfigurasi.md](docs/konfigurasi.md).

## Periksa

```sh
flutter test     # 168 test
dart analyze lib test
```

## Struktur

```
lib/
  config/    Env (nilai build), ApiConfig (alamat aktif), Host (normalisasi alamat)
  services/  ApiClient (Dio), ApiException, ApiLogger, CardReader (NFC)
  data/      ChargePointRepository, ChargingScope, CardReaderScope, formatters
  models/    Spklu, ChargeBox, Connector, SessionInfo, CommandResult, ChargingSession
  pages/     satu berkas per layar Figma
  widgets/   komponen bersama (PageScaffold, tombol, kartu, chip)
  theme/     AppColors & AppTheme — token warna dan teks
```

## Melihat lalu lintas API

Tekan lama logo di header halaman mana pun untuk membuka inspektur
jaringan — daftar panggilan REST beserta header dan isinya, seperti tab
Network di peramban. Menyala di build debug; untuk APK release nyalakan
dengan `--dart-define=SPKLU_DEBUG_PANEL=true`. Rinciannya di
[docs/konfigurasi.md](docs/konfigurasi.md#inspektur-jaringan).

## Dokumentasi

| Dokumen | Isi |
|---|---|
| [Arsitektur](docs/arsitektur.md) | Lapisan, aliran data, dan keputusan desain yang menahan bug |
| [Alur layar](docs/alur-layar.md) | Urutan halaman, percabangan status konektor, navigasi |
| [API backend](docs/api-backend.md) | Endpoint, amplop response, kode error, contoh payload |
| [Konfigurasi](docs/konfigurasi.md) | Alamat server, `--dart-define`, HTTP dan sertifikat |
| [Pengujian](docs/pengujian.md) | Peta berkas test dan cara menulis test baru |

## Aset dan branding

Ikon peluncur dan splash dibangkitkan dari berkas di `branding/`:

```sh
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Ikon SVG dan gambar ada di `assets/icons/` dan `assets/images/`.
`AssetSlot` menggambar kotak placeholder bertuliskan nama berkas bila
asetnya belum ada, jadi yang kurang langsung kelihatan di layar.
