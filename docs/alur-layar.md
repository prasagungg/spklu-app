# Alur layar

Satu berkas di `lib/pages/` untuk satu frame Figma. Nomor node ditulis
di komentar kelas masing-masing.

## Peta alur

```
Pilih Charge Box  (charge_box_page.dart)  ← rute pertama
        │  ikon roda gigi ⇄ Konfigurasi Server (api_config_page.dart)
        │  keduanya pushReplacement, jadi hanya satu yang ada di tumpukan
        │  tap kartu charge box → bottom sheet Daftar Konektor
        │
        ├─ konektor bukan "Available" → Verifikasi Sesi
        │
        ├─ Available / Preparing ─────────────────┐
        │                                         ▼
        │                              Pilih Nominal
        │                                         │
        │                              Konfirmasi Pengisian
        │                                         │
        │                              Pembayaran Kartu  ← maju saat kartu ditempelkan
        │                                         │
        │                              Pembayaran Berhasil
        │                                         │
        │                              Hubungkan Konektor  ← perintah start di sini
        │                                         │
        │                              Pengisian Dimulai  ← kode sesi ditunjukkan
        │                                         │  pulang ke daftar
        │                                         ▼
        └─ Charging ──────────────────► Sedang Mengisi
             (verifikasi kode sesi)
                                                  │
                            ┌─────────────────────┴───────────────┐
                            │                                     │
                 Akhiri Pengisian?                    charger berhenti sendiri
                            │  POST /stop                         │
                            └──────────► Pengisian Selesai ◄──────┘
```

## Percabangan status konektor

Status konektor **tidak terlihat dari daftar charge box**. Begitu
bottom sheet terbuka, tiap konektor ditanyakan sekali lewat
`POST /status-konektor`; selama jawabannya belum datang chip-nya
berbunyi "Memeriksa…" dan konektornya belum bisa ditekan.

Sheet lalu mengembalikan konektor yang dipilih, dan tujuannya ditentukan
status hasil pemeriksaan itu — bukan status yang ikut di daftar.

Konektor yang bebas **dikunci lebih dulu** lewat `POST /booked-connector`
tahap R0 sebelum alur pembelian dimulai. Kalau ternyata sudah diambil
orang lain, pengguna diberi tahu dan daftarnya dimuat ulang — lebih baik
berhenti di sini daripada setelah ia membayar. Konektor yang dilanjutkan
dari sesi orang lain (status 2–4) tidak dibooking ulang.

| `status` | Arti | `ConnectorStatus` | Bisa ditekan | Tujuan |
|---|---|---|---|---|
| `1` | Belum dibayar / masih bisa dipakai | `available` | ya | Pilih Nominal |
| `2` | Sudah dibayar, menunggu konektor | `preparing` | ya | Hubungkan Konektor |
| `3` | Sedang mengisi | `inUse` | ya | Sedang Mengisi |
| `4` | Pengisian selesai | `finished` | ya | Sedang Mengisi |

Sesi yang dilanjutkan dari daftar **belum bisa dipantau atau
dihentikan**: endpoint pengisian berkunci `orderId`, dan konektor tidak
membawanya. Layarnya jatuh ke simulasi lokal.
| lainnya | Tidak dikenal | `unavailable` | tidak | — |

Konektor yang **bukan** `1` sudah diklaim orang lain, jadi sebelum
melanjutkan pengguna harus melewati **Verifikasi Sesi** — keypad dua
digit yang membuktikan ia pemilik sesi tersebut.

`4` ikut menuju layar pemantauan karena `/progress` yang jadi penentu:
begitu ia melaporkan `finished`, halaman itu berpindah sendiri ke
rincian akhir dengan angka energi yang benar.

Sesi yang dilanjutkan dari daftar tidak membawa data pembelian —
aplikasi tidak tahu berapa yang sudah dibayarkan — jadi baris
pembayarannya disembunyikan, bukan diisi nol.

Kartu charge box di daftar tidak bisa tahu status konektornya, jadi
hampir selalu bisa ditekan; penyaringannya terjadi di dalam sheet.
`status` milik charge box sendiri belum dipakai — lihat
[api-backend.md](api-backend.md#post-list-chargerbox).

## Kapan perintah dikirim

Ini bagian yang paling mudah salah baca.

| Pemicu | Layar | Yang terjadi |
|---|---|---|
| Konektor ditekan | Daftar Konektor | `POST /booked-connector` **R0** mengunci konektor. Ditolak → alur berhenti di sini. |
| Menunggu di Hubungkan Konektor | Hubungkan Konektor | `POST /manage-sessioncode` tiap detik sampai `statusProcess` menandakan nozzle tercolok. |
| Pilihan kWh ditekan | Pilih Nominal | `POST /count-kwh` menghitung harganya. |
| "Lanjutkan" | Pilih Nominal | Booking naik ke **R1**, lalu `POST /transaction/push-order` membuat ordernya. |
| Kartu ditempelkan | Pembayaran Kartu | `inquiry-billing` menanyakan tagihan, lalu `payment-billing` membayarnya. Keduanya berhasil → booking naik ke **R2** lalu pindah ke Pembayaran Berhasil; gagal di salah satunya → tetap di sini dan kartu bisa ditempelkan ulang. |
| "Mulai Pengisian" | Pembayaran Berhasil | **Tidak** mengirim apa pun. Hanya pindah ke Hubungkan Konektor. |
| "Mulai Pengisian" | Hubungkan Konektor | Booking naik ke **R3**, lalu `POST /transaction/charging/start`, lalu pindah ke Sedang Mengisi. |
| Kembali ke daftar sebelum pengisian jalan | mana pun di alur pembelian | `POST /cancelled-connector` melepas konektornya. |
| "Ya, Akhiri Pengisian" | Akhiri Pengisian? | `POST /transaction/charging/stop`, baca energi akhir lewat `ongoing-kwh`, lalu Pengisian Selesai. |

`/start` sengaja dikirim dari **Hubungkan Konektor**, bukan lebih awal,
supaya perintahnya berangkat sesudah kabel terpasang.

Halaman itu memanggil `POST /manage-sessioncode` tiap detik dan
menunggu `statusProcess` berpindah dari `2` ("hubungkan konektor") ke
`3`. Selama masih `2`, tombolnya mati. Alurnya tetap utuh, tetapi tidak ada jaminan kabel benar-benar
terpasang; charger yang menolak `/start` muncul sebagai pesan error.

Perlu diingat `POST /start` membalas `state: "starting"`, bukan
`"charging"`. Controller baru meneruskan perintah. Konfirmasi bahwa
pengisian benar-benar jalan datang dari polling berikutnya.

## Memilih jumlah kWh

Pilihannya datang dari `GET /list-kwh` saat halaman dibuka, dan harganya
dari `POST /count-kwh` setiap kali salah satu ditekan.

**Tidak ada yang terpilih saat halaman dibuka**, dan tombol "Lanjutkan"
mati sampai ada harga. Pilihan yang sudah tercentang sejak awal gampang
terlewat, dan pengguna bisa membayar jumlah yang tidak pernah ia pilih
sendiri.

Rincian harga baru muncul setelah ada pilihan; sebelum itu tempatnya
diisi keterangan singkat, bukan kartu kosong.

"Lanjutkan" membuat order lewat `POST /transaction/push-order`. Sejak
halaman Konfirmasi, angka yang ditampilkan adalah angka **order** — yang
juga membawa nomor referensi dan kode sesi — bukan perkiraan dari
`/count-kwh`.

## Dua jalan menuju "Pengisian Selesai"

1. **Pengguna menekan Akhiri Pengisian.** `StopConfirmPage` mengirim
   perintah stop, lalu membaca `ongoing-kwh` sampai lima kali sampai
   statusnya `4` untuk mendapat angka energi yang benar.
2. **Charger berhenti sendiri**, misalnya karena kWh yang dipesan sudah
   tersalur. Polling `ongoing-kwh` di halaman Sedang Mengisi melihat
   status `4` dan langsung pindah.

Keduanya berujung ke `ChargingFinishedPage` dengan angka kWh final.

## Navigasi dan tombol pulang

- **Rute pertama adalah Pilih Charge Box.** Aplikasi membukanya
  langsung; Konfigurasi Server bukan layar pembuka. Perpindahan ke dan
  dari layar konfigurasi memakai `pushReplacement`, bukan `push`,
  sehingga tidak ada yang menumpuk. Ini penting karena tombol "Kembali
  ke Halaman Awal" di halaman-halaman lanjutan memakai
  `popUntil((r) => r.isFirst)` — rute pertama harus daftar charge box,
  bukan layar konfigurasi.
- **Meninggalkan alur melepas booking.** Konektor yang dikunci R0 tetap
  terkunci sampai dilepas, jadi setiap jalan keluar dari alur pembelian
  harus membatalkannya. Ketiganya — "Kembali", tombol Home, dan tombol
  kembali perangkat — berujung ke halaman Pilih Charge Box, jadi
  pembatalannya cukup dipasang sekali di `didPopNext()` halaman itu.
  Begitu `POST /start` berhasil bookingnya dilupakan, sehingga pulang
  dari layar pemantauan tidak menghentikan pengisian yang sedang jalan.
- **Tombol Home dipasang otomatis.** `PageScaffold` menaruhnya di ujung
  kanan header pada semua halaman kecuali yang menandai dirinya
  `isHome`, sehingga tidak ada halaman yang lupa menyediakan jalan
  pulang.
- **Konfigurasi Server** dibuka lewat ikon roda gigi di header halaman
  Pilih Charge Box, dan kembali ke sana setelah alamat disimpan.
- **Hitung mundur 10 menit** muncul di Pembayaran Kartu dan Hubungkan
  Konektor sebagai `CountdownPill`.

## Kode sesi

Setelah perintah start berhasil, alur berakhir di **Pengisian Dimulai**
(73:3667) — satu-satunya tempat kode sesi ditampilkan besar. Kodenya
datang dari `POST /transaction/push-order`.

Satu-satunya jalan keluarnya adalah pulang ke daftar charge box,
mengikuti desain. Untuk memantau atau menghentikan pengisiannya,
pengguna menekan konektornya lagi dari daftar itu dan memasukkan kode
tersebut; `POST /manage-sessioncode` yang memeriksanya, dan `orderId`
dari jawabannya dipakai untuk memantau serta menghentikan sesi — jadi
sesi yang dimulai dari unit mana pun bisa dibuka kembali.

Itulah sebabnya layar ini ada: tanpa kode sesi yang benar-benar
membuka sesinya lagi, pengguna tidak akan pernah bisa mengakhiri
pengisiannya sendiri.
