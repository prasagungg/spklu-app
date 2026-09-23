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
        ├─ Available / Reserved ──────────────────┐
        │                                         ▼
        │                              Kode Sesi  ← kode ditunjukkan di sini
        │                                         │
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
        │                              Pengisian Dimulai
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
pengguna menekan sebuah charge box, isinya diambil ulang sekali lewat
`POST /detail-chargerbox` — satu panggilan untuk seluruh konektor.
Selama jawabannya belum datang chip-nya berbunyi "Memeriksa…" dan
konektornya belum bisa ditekan.

Sheet lalu mengembalikan konektor yang dipilih, dan tujuannya ditentukan
status hasil pemeriksaan itu — bukan status yang ikut di daftar.

Konektor yang bebas **dipesan lebih dulu** lewat
`POST /booked-connector` sebelum alur pembelian dimulai. Kalau ternyata
sudah diambil orang lain, pengguna diberi tahu dan daftarnya dimuat
ulang — lebih baik berhenti di sini daripada setelah ia membayar.
Konektor yang dilanjutkan dari sesi orang lain (status 2–4) tidak
dipesan ulang.

Pemesanan itu memberi `reservationId` — yang dibawa `push-order` dan
`cancelled-connector` — serta `sessionCode` dan batas waktunya, yang
langsung ditunjukkan di halaman **Kode Sesi**.

| `status` | Arti | `ConnectorStatus` | Bisa ditekan | Tujuan |
|---|---|---|---|---|
| `0` | Sedang dipesan, belum dibayar | `reserved` | ya | Kode Sesi |
| `1` | Belum dibayar / masih bisa dipakai | `available` | ya | Kode Sesi |
| `2` | Sudah dibayar, menunggu konektor | `preparing` | ya | Hubungkan Konektor |
| `3` | Sedang mengisi | `inUse` | ya | Sedang Mengisi |
| `4` | Pengisian selesai | `finished` | ya | Sedang Mengisi |
| lainnya | Tidak dikenal | `unavailable` | tidak | — |

Sesi yang dilanjutkan dari daftar hanya bisa dipantau dan dihentikan
bila `manage-sessioncode` menyebutkan `orderId`-nya: semua endpoint
pengisian berkunci order, sedangkan konektor tidak membawanya. Tanpa
itu layarnya jatuh ke simulasi lokal.

Konektor yang **bukan** `1` sudah diklaim orang lain, jadi sebelum
melanjutkan pengguna harus melewati **Verifikasi Sesi** — keypad dua
digit yang membuktikan ia pemilik sesi tersebut.

`4` ikut menuju layar pemantauan karena `ongoing-kwh` yang jadi penentu:
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
| Konektor ditekan | Daftar Konektor | `POST /booked-connector` memesan konektor dan memberi kode sesinya. `status: false` → alur berhenti di sini. |
| Menunggu di Hubungkan Konektor | Hubungkan Konektor | `POST /manage-sessioncode` tiap detik sampai `statusProcess` menandakan nozzle tercolok. |
| Pilihan kWh ditekan | Pilih Nominal | `POST /count-kwh` menghitung harganya. |
| "Lanjutkan" | Kode Sesi | **Tidak** mengirim apa pun. Hanya pindah ke Pilih Nominal. |
| "Lanjutkan" | Pilih Nominal | `POST /transaction/push-order` membuat ordernya, dengan `reservationId` dari pemesanan. |
| Kartu ditempelkan | Pembayaran Kartu | `inquiry-billing` menanyakan tagihan, lalu `payment-billing` membayarnya. Keduanya berhasil → pindah ke Pembayaran Berhasil; gagal di salah satunya → tetap di sini dan kartu bisa ditempelkan ulang. |
| "Mulai Pengisian" | Pembayaran Berhasil | **Tidak** mengirim apa pun. Hanya pindah ke Hubungkan Konektor. |
| "Mulai Pengisian" | Hubungkan Konektor | `POST /transaction/charging/start`, lalu pindah ke Sedang Mengisi. |
| Kembali ke daftar sebelum pengisian jalan | mana pun di alur pembelian | `POST /cancelled-connector` melepas pemesanannya. |
| "Ya, Akhiri Pengisian" | Akhiri Pengisian? | `POST /transaction/charging/stop`, baca energi akhir lewat `ongoing-kwh`, lalu Pengisian Selesai. |

`/start` sengaja dikirim dari **Hubungkan Konektor**, bukan lebih awal,
supaya perintahnya berangkat sesudah kabel terpasang.

Halaman itu memanggil `POST /manage-sessioncode` tiap detik dan
menunggu `statusProcess` berpindah dari `2` ("hubungkan konektor") ke
`3`. Selama masih `2`, tombolnya mati. Alurnya tetap utuh, tetapi tidak ada jaminan kabel benar-benar
terpasang; charger yang menolak `/start` muncul sebagai pesan error.

Perintah start hanya diteruskan controller ke charger; konfirmasi bahwa
pengisian benar-benar jalan datang dari polling `ongoing-kwh`
berikutnya.

## Riwayat transaksi

Tiap kartu konektor di bottom sheet punya tombol struk yang membuka
**Riwayat Transaksi** (Figma 189:761) untuk konektor itu. Pintu masuknya
di situ karena `POST /transaction/history-transaction` meminta nomor
charge box **dan** konektor, dan hanya di sheet itu keduanya ada di
tangan sekaligus.

Tiap barisnya: nomor dan nama charge box, tipe konektor, waktu, nominal,
dan nomor kartu yang disamarkan.

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
- **Meninggalkan alur melepas pemesanan.** Konektor yang dipesan tetap
  terkunci sampai dilepas, jadi setiap jalan keluar dari alur pembelian
  harus membatalkannya. Keempatnya — "Kembali", "Batalkan Transaksi" di
  halaman Kode Sesi, tombol Home, dan tombol kembali perangkat —
  berujung ke halaman Pilih Charge Box, jadi pembatalannya cukup
  dipasang sekali di `didPopNext()` halaman itu. Mundur satu langkah
  dari Pilih Nominal ke Kode Sesi tidak membatalkan apa pun. Begitu
  perintah start berhasil pemesanannya dilupakan, sehingga pulang dari
  layar pemantauan tidak menghentikan pengisian yang sedang jalan.
- **Tombol Home dipasang otomatis.** `PageScaffold` menaruhnya di ujung
  kanan header pada semua halaman kecuali yang menandai dirinya
  `isHome`, sehingga tidak ada halaman yang lupa menyediakan jalan
  pulang.
- **Konfigurasi Server** dibuka lewat ikon roda gigi di header halaman
  Pilih Charge Box, dan kembali ke sana setelah alamat disimpan.
- **Hitung mundur** muncul di Kode Sesi, Pembayaran Kartu, dan
  Hubungkan Konektor sebagai `CountdownPill`. Di Kode Sesi angkanya
  datang dari `sessionExpired` milik pemesanan; di dua halaman lain
  masih sepuluh menit tetap.

## Kode sesi

Kode sesi ditunjukkan **dua kali**, dan keduanya datang dari
`POST /booked-connector`:

1. **Kode Sesi** (203:3352), tepat setelah konektor dipesan — sebelum
   nominal dipilih, apalagi dibayar. Isinya kode besar, keterangan
   "Catat atau foto kode ini", kartu konektor yang dipilih, lalu
   "Lanjutkan" dan "Batalkan Transaksi". Hitung mundurnya memakai
   `sessionExpired`.
2. **Pengisian Dimulai** (73:3667), setelah perintah start berhasil.

Menunjukkannya sejak awal disengaja: kalau pengguna pergi di tengah alur
— kartunya tertinggal, antreannya panjang — ia tetap memegang kode untuk
kembali ke sesinya.

Satu-satunya jalan keluar dari Pengisian Dimulai adalah pulang ke daftar
charge box, mengikuti desain. Untuk memantau atau menghentikan
pengisiannya,
pengguna menekan konektornya lagi dari daftar itu dan memasukkan kode
tersebut; `POST /manage-sessioncode` yang memeriksanya, dan `orderId`
dari jawabannya dipakai untuk memantau serta menghentikan sesi — jadi
sesi yang dimulai dari unit mana pun bisa dibuka kembali.

Itulah sebabnya layar ini ada: tanpa kode sesi yang benar-benar
membuka sesinya lagi, pengguna tidak akan pernah bisa mengakhiri
pengisiannya sendiri.
