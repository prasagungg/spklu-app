# Alur layar

Satu berkas di `lib/pages/` untuk satu frame Figma. Nomor node ditulis
di komentar kelas masing-masing.

## Peta alur

```
Konfigurasi Server  (api_config_page.dart)
        │  Hubungkan / Lanjut Tanpa Uji → pushReplacement
        ▼
Pilih Charge Box  (charge_box_page.dart)  ← rute pertama
        │  tap kartu → bottom sheet Daftar Konektor
        │
        ├─ konektor bukan "Available" → Verifikasi Sesi
        │
        ├─ Available / Preparing ─────────────────┐
        │                                         ▼
        │                              Pilih Nominal
        │                                         │
        │                              Konfirmasi Pengisian
        │                                         │
        │                              Pembayaran Kartu
        │                                         │
        │                              Pembayaran Berhasil
        │                                         │
        │                              Hubungkan Konektor  ← POST /start di sini
        │                                         │
        └─ Charging ──────────────────► Sedang Mengisi
                                                  │
                            ┌─────────────────────┴───────────────┐
                            │                                     │
                 Akhiri Pengisian?                    charger berhenti sendiri
                            │  POST /stop                         │
                            └──────────► Pengisian Selesai ◄──────┘
```

## Percabangan status konektor

Bottom sheet mengembalikan konektor yang dipilih; tujuannya ditentukan
statusnya.

| Status OCPP | `ConnectorStatus` | Bisa ditekan | Tujuan |
|---|---|---|---|
| `Available` | `available` | ya | Pilih Nominal |
| `Preparing` | `preparing` | ya | Pilih Nominal |
| `Charging`, `SuspendedEV`, `SuspendedEVSE`, `Finishing` | `inUse` | ya | Sedang Mengisi (sesi lanjutan) |
| `Reserved`, `Unavailable`, `Faulted`, tak dikenal | `unavailable` | tidak | — |

`errorCode` selain `NoError` membuat konektor `unavailable` sekalipun
statusnya masih `Available`.

`Preparing` diperlakukan sama seperti `Available`: kabel memang sudah
tercolok, tetapi belum ada transaksi, jadi pengguna tetap membeli dulu.

Konektor yang **bukan** `Available` sudah diklaim orang lain, jadi
sebelum melanjutkan pengguna harus melewati **Verifikasi Sesi** — keypad
dua digit yang membuktikan ia pemilik sesi tersebut.

## Kapan perintah dikirim

Ini bagian yang paling mudah salah baca.

| Tombol | Layar | Yang terjadi |
|---|---|---|
| "Mulai Pengisian" | Pembayaran Berhasil | **Tidak** mengirim apa pun. Hanya pindah ke Hubungkan Konektor. |
| "Mulai Pengisian" | Hubungkan Konektor | `POST /start`, lalu pindah ke Sedang Mengisi. |
| "Ya, Akhiri Pengisian" | Akhiri Pengisian? | `POST /stop`, baca energi akhir, lalu Pengisian Selesai. |

`/start` sengaja dikirim dari **Hubungkan Konektor**, bukan lebih awal.
Halaman itu mem-polling `/list` sampai status konektor berubah dari
`Available` menjadi `Preparing` — tanda kabel benar-benar tercolok ke
kendaraan. Tombolnya mati sampai saat itu. Mengirim `/start` sebelum
konektor terpasang akan ditolak charger.

Perlu diingat `POST /start` membalas `state: "starting"`, bukan
`"charging"`. Controller baru meneruskan perintah. Konfirmasi bahwa
pengisian benar-benar jalan datang dari polling berikutnya.

## Dua jalan menuju "Pengisian Selesai"

1. **Pengguna menekan Akhiri Pengisian.** `StopConfirmPage` mengirim
   `/stop`, lalu membaca `/progress` sampai lima kali sampai `state`
   menjadi `"finished"` untuk mendapat angka energi yang benar.
2. **Charger berhenti sendiri**, misalnya karena `targetKwh` tercapai.
   Polling `/progress` di halaman Sedang Mengisi melihat
   `state: "finished"` dan langsung pindah.

Keduanya berujung ke `ChargingFinishedPage` dengan angka kWh final.

## Navigasi dan tombol pulang

- **Rute pertama adalah Pilih Charge Box.** Halaman Konfigurasi Server
  memakai `pushReplacement`, bukan `push`, sehingga ia tidak menumpuk di
  bawah. Ini penting karena tombol "Kembali ke Halaman Awal" di
  halaman-halaman lanjutan memakai `popUntil((r) => r.isFirst)` — rute
  pertama harus daftar charge box, bukan layar konfigurasi.
- **Tombol Home dipasang otomatis.** `PageScaffold` menaruhnya di ujung
  kanan header pada semua halaman kecuali yang menandai dirinya
  `isHome`, sehingga tidak ada halaman yang lupa menyediakan jalan
  pulang.
- **Kembali ke konfigurasi** lewat ikon roda gigi di header halaman
  Pilih Charge Box, juga dengan `pushReplacement` demi alasan yang sama.
- **Hitung mundur 10 menit** muncul di Pembayaran Kartu dan Hubungkan
  Konektor sebagai `CountdownPill`.

## Halaman yang tidak dipakai

`charging_started_page.dart` (frame "Pengisian Dimulai") tidak ada di
alur. Setelah `/start` aplikasi langsung menuju Sedang Mengisi agar
start, stop, dan pemantauan berada dalam satu layar. Halamannya
dipertahankan karena merupakan satu-satunya tempat kode sesi ditampilkan
besar — pasang kembali bila layar itu dibutuhkan.
