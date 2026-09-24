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
        ├─ konektor bukan "Tersedia" → Verifikasi Sesi
        │
        ├─ Tersedia / Dipesan ────────────────────┐
        │                                         ▼
        │                              Kode Sesi  ← kode ditunjukkan di sini
        │                                         │
        │                              Pilih Nominal
        │                                         │
        │                              Konfirmasi Pengisian
        │                                         │
        │                              Pembayaran Kartu  ← maju saat kartu ditempelkan
        │                              ▲          │
        │        Menunggu Pembayaran ──┘          │
        │        (verifikasi kode sesi)           │
        │                              Pembayaran Berhasil
        │                                         │
        │                              Hubungkan Konektor  ← perintah start di sini
        │                                         │
        │                              Pengisian Dimulai
        │                                         │  pulang ke daftar
        │                                         ▼
        └─ Sedang Digunakan ──────────► Sedang Mengisi
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
| `0` | Sudah dipesan, belum dibeli | `reserved` | ya | Kode Sesi |
| `1` | Tersedia | `available` | ya | Kode Sesi |
| `2` | Sedang digunakan | `inUse` | ya | Sedang Mengisi |
| `3` | Menunggu pembayaran | `awaitingPayment` | ya | Pembayaran |
| `4` | Tidak tersedia | `unavailable` | tidak | — |
| lainnya | Tidak dikenal | `unavailable` | tidak | — |

Sesi yang dilanjutkan masuk **tepat di langkah tempat ia berhenti**:
yang ordernya belum dibayar kembali ke halaman Pembayaran — nominalnya
ditanyakan ulang lewat `inquiry-billing` begitu kartu ditempelkan — dan
yang sedang dipakai langsung ke layar pemantauan.

Sesi yang dilanjutkan dari daftar hanya bisa dipantau dan dihentikan
bila `manage-sessioncode` menyebutkan `orderId`-nya: semua endpoint
pengisian berkunci order, sedangkan konektor tidak membawanya. Tanpa
itu layarnya jatuh ke simulasi lokal.

Konektor yang **bukan** `1` sudah diklaim orang lain, jadi sebelum
melanjutkan pengguna harus melewati **Verifikasi Sesi** — keypad dua
digit yang membuktikan ia pemilik sesi tersebut.

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
| Menunggu di Hubungkan Konektor | Hubungkan Konektor | `POST /check-status-connector` tiap detik sampai status OCPP-nya `Preparing` — tanda kabel sudah tercolok. |
| Pilihan kWh ditekan | Pilih Nominal | `POST /count-kwh` menghitung harganya. |
| "Lanjutkan" | Kode Sesi | **Tidak** mengirim apa pun. Hanya pindah ke Pilih Nominal. |
| "Lanjutkan" | Pilih Nominal | `POST /transaction/push-order` membuat ordernya, dengan `reservationId` dari pemesanan. |
| Kartu ditempelkan | Pembayaran Kartu | `inquiry-billing` menanyakan tagihan, lalu `payment-billing` membayarnya. Keduanya berhasil → pindah ke Pembayaran Berhasil; gagal di salah satunya → tetap di sini dan kartu bisa ditempelkan ulang. Tagihan bernilai nol — tanda tarif konektornya belum diatur — dihentikan sebelum dibayar. |
| "Mulai Pengisian" | Pembayaran Berhasil | **Tidak** mengirim apa pun. Hanya pindah ke Hubungkan Konektor. |
| "Mulai Pengisian" | Hubungkan Konektor | `POST /transaction/charging/start`, lalu pindah ke Sedang Mengisi. |
| Kembali ke daftar sebelum pengisian jalan | mana pun di alur pembelian | `POST /cancelled-connector` melepas pemesanannya. |
| "Ya, Akhiri Pengisian" | Akhiri Pengisian? | `POST /transaction/charging/stop`, baca energi akhir lewat `ongoing-kwh`, lalu Pengisian Selesai. |

`/start` sengaja dikirim dari **Hubungkan Konektor**, bukan lebih awal,
supaya perintahnya berangkat sesudah kabel terpasang.

Halaman itu memanggil `POST /check-status-connector` tiap detik dan
menunggu status OCPP konektornya menjadi `Preparing` — istilah untuk
kabel yang sudah terpasang dan charger yang siap dimulai. Selama masih
`Available`, tombolnya mati. `Faulted` dan `Unavailable` disebut apa
adanya di layar: charger seperti itu tidak akan pernah sampai ke
`Preparing`, jadi menunggu di situ tidak ada gunanya.

Perintah start hanya diteruskan controller ke charger; konfirmasi bahwa
pengisian benar-benar jalan datang dari polling `ongoing-kwh`
berikutnya.

## Riwayat transaksi

Tombol struk di header halaman Pilih Charge Box — di sebelah ikon roda
gigi — membuka **Riwayat Transaksi** (Figma 189:761) untuk **seluruh
lokasi**.

`GET /transaction/history-transaction` mengembalikan seluruh riwayat
dalam satu panggilan, tanpa body dan tanpa query. Halaman ini karena
itu hanya mengurutkannya terbaru lebih dulu. Endpoint ini dulu sebuah
POST yang melayani satu konektor sekali panggil — tanpa `chargeBoxId`
atau `connectorId` dibalas `07` "Missing Field" — sehingga halaman
menanyakan tiap konektor lalu menggabungkan jawabannya.

Tiap barisnya (Figma 204:6137): nomor dan nama charge box, nama dan
tipe konektor, waktu, nominal, dan nomor kartu yang disamarkan. Charge
box dan konektornya disebut tiap entri; nomor urut dan dayanya
dicocokkan ke daftar charge box, karena hanya `POST /list-chargerbox`
yang mengirim keduanya. Entri dari charge box yang tidak ada di daftar
tetap tampil, memakai nama dari entrinya sendiri dan tanpa nomor urut.

**Kotak pencarian** di atas daftar menyaring tanggal, nama charger, dan
nominal sekaligus. Penyaringannya di aplikasi: seluruh riwayat lokasi
sudah ada di tangan, dan endpoint-nya tidak menerima kata kunci apa pun.

## Rincian satu transaksi

Kartu riwayat bisa ditekan, dan chevron di sisi kanannya menandai itu.
Menekannya meminta **kode sesi** transaksi tersebut lebih dulu — keypad
yang sama dengan Verifikasi Sesi — lalu membuka **Detail Transaksi**.

Pembagiannya disengaja dan mengikuti backend: daftar riwayat boleh
dilihat siapa saja yang berdiri di depan unit, karena isinya hanya
waktu, nominal, dan nomor kartu yang disamarkan. Rinciannya tidak —
`POST /transaction/detail-history-transaction` mewajibkan kode sesi, dan
kode yang salah dibalas `21` sehingga alurnya berhenti di keypad.

Halaman rinciannya menampilkan tiga kartu — charger, energi, dan
pembayaran — dengan "Pembayaran Awal" sebagai baris yang ditonjolkan.
Semua angkanya dari backend; tidak ada yang dihitung di aplikasi.

## Memilih jumlah kWh

Frame 204:3670. Pilihannya datang dari `GET /list-kwh` saat halaman
dibuka, dan harganya dari `POST /count-kwh` setiap kali salah satu
ditekan. Kartunya tiga per baris, berisi ikon petir dan angkanya saja
("10", bukan "10,0 kWh") — cukup sempit untuk memuat tujuh pilihan
tanpa menggulir.

Hitung mundurnya duduk sebaris dengan judul, dan **meneruskan batas
waktu pemesanan** (`sessionExpired`) — halaman ini menunjukkan sisa
waktu yang sama dengan halaman Kode Sesi, bukan sepuluh menit yang
dimulai ulang.

**Tidak ada yang terpilih saat halaman dibuka**, dan tombol "Lanjutkan"
mati sampai ada harga. Pilihan yang sudah tercentang sejak awal gampang
terlewat, dan pengguna bisa membayar jumlah yang tidak pernah ia pilih
sendiri.

Rincian harga baru muncul setelah ada pilihan; sebelum itu tempatnya
diisi keterangan singkat, bukan kartu kosong.

**Total Rp0 menghentikan alur di sini.** Konektor yang tarifnya belum
diatur di server dihargai nol oleh `count-kwh`, dan tagihan nol pasti
ditolak backend saat membayar ("Missing Field: amount"). "Lanjutkan"
karena itu tetap mati, dengan keterangan yang menyebut sebabnya.

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

Keduanya berujung ke `ChargingFinishedPage`, yang lalu menanyakan
`POST /transaction/charging/detail` untuk angka penutupnya: energi
tersalur, pembayaran awal, total pemakaian, dan sisa pembayaran. Selama
jawabannya belum datang — atau kalau gagal, dan pada sesi tanpa order —
yang ditampilkan adalah angka terakhir dari layar pemantauan.

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
  Pilih Charge Box, dan kembali ke sana setelah alamat disimpan. Di
  sebelahnya ada tombol struk menuju Riwayat Transaksi.
- **Hitung mundur** muncul lewat `ExpiryCountdown`, yang berdetak
  sendiri sampai batas waktu yang diberikan. Kode Sesi, Pembayaran
  Kartu, dan Hubungkan Konektor memakai pil lebar "Selesaikan dalam:
  09:59"; Pilih Nominal memakai pil kecil sebaris judul (204:4690).
  Batas waktunya datang dari `sessionExpired` milik pemesanan, dan
  halaman yang belum menerimanya jatuh ke sepuluh menit.

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
