# Konfigurasi

## Alamat server

Alamat edge controller diatur dari dalam aplikasi, bukan saat build.
Halaman pertama yang muncul adalah **Konfigurasi Server**
(`lib/pages/api_config_page.dart`).

Alasannya: controller kerap dipasang di jaringan lokal, berpindah IP,
dan tidak punya nama domain. Membangun ulang APK setiap kali alamatnya
berubah tidak masuk akal di lapangan.

Yang terjadi di halaman itu:

1. Kolom alamat terisi alamat yang sedang dipakai — alamat terakhir yang
   disimpan operator, atau nilai bawaan `SPKLU_API_BASE_URL` bila belum
   pernah ada.
2. Di bawah kolom ada pratinjau alamat yang benar-benar akan ditembak,
   misalnya `Akan memanggil http://192.168.1.10:8080/list`. Ini membuat
   salah ketik ketahuan sebelum tombol ditekan — termasuk saat prefiks
   path seperti `/api` lupa disertakan.
3. **Hubungkan** memasang alamat, mengujinya dengan `GET /list`, lalu
   masuk ke daftar charge box. Alamat yang gagal dihubungi **tidak**
   disimpan, supaya salah ketik tidak ikut teringat.
4. **Lanjut Tanpa Uji** langsung masuk. Berguna bila controller sedang
   mati tetapi operator tetap ingin melihat halaman daftar, yang punya
   penanganan gagal dan coba-ulang sendiri.

Alamat yang tersimpan bertahan setelah aplikasi ditutup
(`shared_preferences`, kunci `spklu_api_base_url`). Kegagalan menyimpan
tidak menghalangi operator masuk — alamatnya tetap aktif untuk sesi itu.

Untuk menggantinya kemudian, tekan ikon roda gigi di header halaman
Pilih Charge Box.

## Menulis alamat

`Host.normalizeBaseUrl()` (`lib/config/host.dart`) membereskan alamat
yang ditulis seadanya:

| Diketik | Dipakai |
|---|---|
| `192.168.1.10:8080` | `http://192.168.1.10:8080` |
| `10.0.2.2` | `http://10.0.2.2` |
| `http://host:8080/` | `http://host:8080` |
| `https://host/api` | `https://host/api` |
| `  192.168.1.10:8080  ` | `http://192.168.1.10:8080` |

Dua aturannya:

- **Tanpa skema dianggap `http://`.** Perangkat di jaringan lokal jarang
  memakai TLS, dan tanpa skema Dio menolak alamatnya.
- **Garis miring di ujung dibuang.** Dio menggabungkan base URL dengan
  path relatif yang sudah berawalan `/`, jadi garis miring di ujung
  hanya menghasilkan `//`.

## HTTP polosan

Alamat `http://` bekerja apa adanya. `android:usesCleartextTraffic="true"`
sudah dipasang di `android/app/src/main/AndroidManifest.xml`, dan tidak
ada `networkSecurityConfig` yang menimpanya.

Kalau nanti `networkSecurityConfig` ditambahkan untuk keperluan lain,
ingat bahwa berkas itu **mengalahkan** `usesCleartextTraffic` — HTTP ke
IP lokal akan ikut mati kecuali domainnya didaftarkan sebagai
pengecualian.

## Sertifikat TLS

Edge controller di jaringan lokal biasanya memakai sertifikat
self-signed. `ApiClient` menerimanya, tetapi **hanya** untuk alamat di
jaringan privat. Host publik tetap diverifikasi penuh.

Yang dianggap privat (`Host.isPrivateHost`):

| Rentang | Keterangan |
|---|---|
| `localhost`, `*.local` | Perangkat ini sendiri dan mDNS |
| `10.0.0.0/8` | Termasuk `10.0.2.2`, alamat host dari emulator Android |
| `127.0.0.0/8` | Loopback |
| `172.16.0.0/12` | |
| `192.168.0.0/16` | |
| `100.64.0.0/10` | CGNAT dan Tailscale |

Dua lapis penjagaannya:

1. Adapter dengan `badCertificateCallback` hanya dipasang bila base
   URL-nya privat.
2. Callback itu sendiri memeriksa ulang host tiap koneksi, jadi
   pengalihan ke host publik tetap ditolak.

Kebijakan ini **dihitung ulang setiap kali alamat diganti**, bukan
disetel sekali saat aplikasi dibangun. Kalau tidak, kelonggaran yang
diberikan untuk IP lokal akan ikut terbawa ketika operator berpindah ke
host publik.

Alamat `http://` tidak terpengaruh sama sekali — koneksi tanpa TLS tidak
pernah sampai ke pemeriksaan sertifikat.

## `--dart-define`

Nilai build. Semuanya opsional.

```sh
flutter run \
  --dart-define=SPKLU_API_BASE_URL=10.0.2.2:8080 \
  --dart-define=SPKLU_API_AUTH="Basic ZWRnZTplZGdlLWRldi1vbmx5" \
  --dart-define=SPKLU_SESSION_PIN=42 \
  --dart-define=SPKLU_API_LOG=false
```

| Nama | Bawaan | Arti |
|---|---|---|
| `SPKLU_API_BASE_URL` | `https://edge-controller-playground.lentera-app.id/api` | Alamat awal di kolom Konfigurasi Server. Bukan alamat final — operator bisa menggantinya. |
| `SPKLU_API_AUTH` | kosong | Isi header `Authorization`. Kosong berarti header-nya tidak dikirim; endpoint playground menerima request tanpa auth. |
| `SPKLU_SESSION_PIN` | `00` | Kode yang diterima halaman Verifikasi Sesi. Masih nilai tetap karena backend belum menyediakan cara memverifikasi kode sesi milik pengguna. |
| `SPKLU_API_LOG` | `true` | Menulis request/response ke konsol. Otomatis mati di build release apa pun nilainya. |

Header `Authorization` juga bisa diganti saat runtime lewat
`ApiClient.instance.authorization = '…'`, misalnya setelah login.

## Nilai tetap di `Env`

Tidak bisa diubah tanpa mengubah kode. Ada di `lib/config/env.dart`.

| Nama | Nilai | Dipakai |
|---|---|---|
| `listRefreshInterval` | 2 detik | Penyegaran daftar charge box |
| `connectorPollInterval` | 2 detik | Menunggu konektor tercolok |
| `progressPollInterval` | 1 detik | Polling energi tersalur |
| `connectTimeout` | 15 detik | Dio |
| `receiveTimeout` | 20 detik | Dio |
| `sendTimeout` | 20 detik | Dio |

## Lapisan konfigurasi

Tiga berkas dengan peran yang berbeda — mudah tertukar:

| Berkas | Peran |
|---|---|
| `config/env.dart` | Nilai dari `--dart-define` dan konstanta build. **Hanya nilai awal**, bukan alamat yang berlaku. |
| `config/host.dart` | Fungsi murni: normalisasi alamat dan pengenalan jaringan privat. Tidak menyimpan state. |
| `config/api_config.dart` | Alamat yang **sedang** dipakai. `restore()` membaca dari penyimpanan sebelum frame pertama, `apply()` memasang tanpa menyimpan, `remember()` menyimpan. |

`ApiConfig.apply()` menerima parameter `client` opsional. Di produksi
client-nya memang `ApiClient.instance`, tetapi menyebutkannya menjaga
agar alamat baru tetap sampai ke client yang benar ketika repository
disuntik — misalnya di test.
