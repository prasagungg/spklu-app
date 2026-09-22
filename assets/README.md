    ant# Assets

Semua asset di bawah ini diekspor langsung dari Figma
**SPKLU Offline Mode** (canvas `UI UX`, file `zKM5CTLRa9DTWE5bPAbDbA`),
kecuali font Inter yang diambil dari rilis resmi rsms/inter v4.1.

```
assets/
├── fonts/Inter/   Inter Regular/Medium/SemiBold/Bold + OFL.txt
├── images/        gambar besar
└── icons/         ikon dalam kartu dan tombol
```

## images/

| File                  | Node Figma | Ukuran render | Dipakai di                       |
|-----------------------|------------|---------------|----------------------------------|
| `logo_spklu.png`      | 70:1906    | 44dp tinggi   | mobile header semua halaman; PNG punya area kosong lebar, di-crop ulang oleh widget `LogoImage` |
| `station.png`         | 70:1903    | 176×176       | pojok kanan atas Pilih Charge Box (desain 127, diperbesar atas permintaan) |
| `bg_page.png`         | 70:1902    | full-bleed    | background, opacity 50%          |
| `card_corner.svg`     | 70:1918    | 108×46        | ornamen sudut kartu charge box   |
| `ornament_bottom.png` | 70:2306    | 223×149       | belum dipakai — di desain posisinya di bawah garis lipat 640dp |

## icons/

| File                     | Node Figma | Ukuran render | Dipakai di                    |
|--------------------------|------------|---------------|-------------------------------|
| `ic_refresh.svg`         | 70:1912    | 20×20         | belum dipakai — tombol refresh dihapus dari header |
| `ic_chevron.svg`         | 70:1932    | 20×20         | tombol lanjut di kartu        |
| `ic_chevron_alt.svg`     | 70:2027    | 20×20         | varian kartu "Last Container" |
| `ic_plug.svg`            | 70:1928    | 16×16         | baris "1 Konektor"            |
| `ic_plug_disabled.svg`   | 70:1960    | 16×16         | baris "1 Konektor" nonaktif   |
| `ic_plug_alt.svg`        | 70:2023    | 16×16         | varian "2 Konektor"           |
| `ic_close.svg`           | 70:2486    | 20×20         | tombol tutup bottom sheet     |
| `ic_connector_ccs2.svg`  | 70:2492    | 24×24         | kartu konektor di bottom sheet|
| `ic_clock.svg`           | 70:2519    | 16×16         | "Est. 15 menit"               |
| `ic_money.svg`           | 70:2249    | 16×16         | kartu nominal belum terpilih  |
| `ic_money_active.svg`    | 70:2258    | 16×16         | kartu nominal terpilih        |
| `ic_arrow_right.svg`     | 69:1813    | 18×18         | tombol "Lanjutkan"            |

## Asset halaman lanjutan

Ditambahkan untuk alur Konfirmasi → Pembayaran → Pengisian.

| File | Node Figma | Dipakai di |
|---|---|---|
| `images/bg_payment.png` | 73:2777 | latar penuh halaman Pembayaran Kartu |
| `images/success_check.png` | 73:3256 | ilustrasi Pembayaran Berhasil (180×120) |
| `images/connector_plug.png` | 73:3567 | Hubungkan Konektor |
| `images/connector_connected.png` | 73:3791 | Konektor Terhubung |
| `images/charging_car.png` | 73:4548 | Pengisian Dimulai |
| `images/hint_strip.png` | 73:3596 | pita gradasi di balik teks bantuan |
| `images/ic_wallet.png` | 73:2926 | kartu info Nominal (28×28) |
| `images/ic_session_lock.png` | 73:2931 | kartu info Kode Sesi (28×28) |
| `images/session_corner_a.svg` | 73:3738 | ornamen kartu kode sesi (130×56) |
| `images/session_corner_b.svg` | 73:3709 | ornamen kartu kode sesi (97×42) |
| `icons/ic_home.svg` | 73:3761 | tombol Home di header |
| `icons/ic_home_filled.svg` | 73:3785 | tombol "Kembali ke Halaman Awal" |
| `icons/ic_charge_box.svg` | 73:2700 | baris Charge Box di Konfirmasi (20×20) |
| `icons/ic_connector.svg` | 73:2728 | baris Konektor di Konfirmasi (20×20) |
| `icons/ic_nominal.svg` | 73:2721 | baris Nominal di Konfirmasi (20×20) |
| `icons/ic_card_pay.svg` | 73:2768 | tombol "Konfirmasi & Bayar" (18×18) |
| `icons/ic_timer.svg` | 73:2852 | pil hitung mundur (20×20) |
| `icons/ic_spinner.svg` | 73:2911 | panel menunggu, diputar oleh kode (24×24) |
| `icons/ic_support.svg` | 73:2858 | tombol Bantuan (18 atau 28) |
| `icons/ic_play.svg` | 73:3428 | tombol "Mulai Pengisian" (18×18) |
| `icons/ic_check_badge.svg` | 73:3655 | lencana centang Konektor Terhubung (36×36) |
| `icons/ic_chevron_down.svg` | 35:328 | pelipat Detail Transaksi (20×20) |
| `icons/ic_info_circle.svg` | 73:3733 | catatan kaki Pengisian Dimulai (20×20) |

## Menambah atau mengganti asset

Ekspor ulang dari Figma lalu timpa file dengan nama yang sama — tidak ada
perubahan kode yang diperlukan. Ukuran render diatur di call site lewat
widget `AssetSlot`, bukan di file asset-nya.

`AssetSlot` mengenali `.svg` (lewat `flutter_svg`) dan `.png` secara
otomatis, dan menggambar kotak placeholder bernama file bila asset-nya
hilang — jadi asset yang belum ada tidak membuat aplikasi crash.
