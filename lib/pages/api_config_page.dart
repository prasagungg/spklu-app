import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/host.dart';
import '../data/charging_scope.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import 'charge_box_page.dart';

/// Alamat edge controller dan kredensial penandatangannya diatur di
/// sini.
///
/// Dibuka lewat ikon roda gigi di header halaman Pilih Charge Box —
/// bukan sebagai layar pembuka. Aplikasi langsung masuk ke daftar
/// charge box memakai alamat yang tersimpan; halaman ini hanya
/// diperlukan saat alamatnya berubah.
///
/// Controller kerap berpindah IP dan dipasang di jaringan lokal tanpa
/// nama domain, jadi alamatnya harus bisa diatur di lapangan. Yang
/// diketik boleh sependek `192.168.1.10:8080` — [Host.normalizeBaseUrl]
/// melengkapinya menjadi `http://192.168.1.10:8080`.
///
/// `client-id` dan secret key ikut di sini karena keduanya bisa
/// dirotasi tanpa aplikasi dibangun ulang. Secret key menandatangani
/// setiap request, jadi kolomnya disamarkan seperti kata sandi —
/// tablet ini berdiri di tempat umum — dan disimpan terenkripsi, bukan
/// sebagai teks polos. Lihat [ApiConfig].
///
/// Nilai baru dipakai langsung, tetapi baru disimpan setelah terbukti
/// bisa dihubungi, supaya salah ketik tidak ikut teringat. Uji
/// koneksinya sekaligus membuktikan kredensialnya benar: tanda tangan
/// yang salah ditolak backend.
class ApiConfigPage extends StatefulWidget {
  const ApiConfigPage({super.key});

  /// Key kolom-kolomnya, dipakai test.
  static const fieldKey = Key('api-base-url-field');
  static const clientIdKey = Key('api-client-id-field');
  static const secretKey = Key('api-secret-key-field');

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage> {
  late final TextEditingController _controller = TextEditingController(
    text: ApiConfig.baseUrl,
  );
  late final TextEditingController _clientId = TextEditingController(
    text: ApiConfig.clientId,
  );
  late final TextEditingController _secret = TextEditingController(
    text: ApiConfig.secretKey,
  );

  bool _testing = false;

  /// Secret key tersamar sampai operator memintanya terlihat — ia perlu
  /// bisa memeriksa ketikannya, tapi tidak sepanjang waktu.
  bool _secretVisible = false;

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _clientId.dispose();
    _secret.dispose();
    super.dispose();
  }

  String get _typed => _controller.text.trim();

  /// Ketiganya wajib: tanda tangan yang dibentuk dari kredensial kosong
  /// pasti ditolak backend, dan gagalnya baru ketahuan di halaman
  /// berikutnya.
  bool get _canSubmit =>
      _typed.isNotEmpty &&
      _clientId.text.trim().isNotEmpty &&
      _secret.text.isNotEmpty &&
      !_testing;

  /// Memasang ketiga nilai sekaligus. Tanda tangannya dibentuk ulang
  /// tiap request dari [ApiConfig], jadi uji koneksi sesudah ini sudah
  /// memakai kredensial yang baru diketik.
  void _applyTyped(ApiClient? client) => ApiConfig.apply(
    baseUrl: _typed,
    clientId: _clientId.text.trim(),
    secretKey: _secret.text,
    client: client,
  );

  /// Memasang alamat, memastikan bisa dihubungi, lalu masuk ke daftar
  /// charge box.
  ///
  /// Ujinya memakai `POST /list-chargerbox` — endpoint yang juga
  /// dipakai halaman berikutnya, jadi kalau lolos di sini halaman itu
  /// pasti jalan.
  Future<void> _connect() async {
    if (!_canSubmit) return;

    FocusScope.of(context).unfocus();
    final repository = ChargingScope.maybeOf(context)?.repository;

    setState(() {
      _testing = true;
      _error = null;
    });

    _applyTyped(repository?.client);
    debugPrint(
      '[CONFIG] Menguji koneksi ke ${ApiConfig.baseUrl}/list-chargerbox',
    );

    // Tanpa scope (mode offline untuk test) tidak ada yang bisa diuji.
    if (repository != null) {
      try {
        await repository.fetchChargeBoxes();
      } on ApiException catch (e) {
        _showFailure(e.message);
        return;
      } on Object catch (e) {
        _showFailure('Alamat tidak bisa dihubungi: $e');
        return;
      }
    }

    await _rememberAndOpen();
  }

  /// Masuk tanpa menguji — dipakai bila controller sedang mati tetapi
  /// operator tetap ingin melihat halaman daftar, yang punya penanganan
  /// gagal dan coba-ulang sendiri.
  Future<void> _skipTest() async {
    if (!_canSubmit) return;

    FocusScope.of(context).unfocus();
    _applyTyped(ChargingScope.maybeOf(context)?.repository.client);
    await _rememberAndOpen();
  }

  void _showFailure(String message) {
    if (!mounted) return;
    setState(() {
      _testing = false;
      _error = message;
    });
  }

  Future<void> _rememberAndOpen() async {
    await ApiConfig.remember();
    if (!mounted) return;

    final navigator = Navigator.of(context);
    // Dibuka dari halaman Pengaturan: pulang ke daftar charge box, yang
    // memuat ulang dirinya begitu terlihat lagi — dengan alamat baru.
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }

    // Belum ada apa pun di tumpukan (mis. alamat diatur sebelum daftar
    // pernah terbuka): daftar charge box yang menggantikannya.
    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ChargeBoxPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Konfigurasi Server',
      subtitle:
          'Masukkan alamat edge controller dan kredensial yang akan '
          'dipakai aplikasi ini.',
      // Tombol Home muncul bila ada tempat untuk pulang. Saat halaman
      // ini satu-satunya di tumpukan — alamat diatur sebelum daftar
      // pernah terbuka — tombolnya tidak ada gunanya.
      isHome: !Navigator.of(context).canPop(),
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        children: [
          PrimaryButton(
            label: _testing ? 'Menghubungkan…' : 'Hubungkan',
            onPressed: _canSubmit ? _connect : null,
          ),
          SecondaryButton(
            label: 'Lanjut Tanpa Uji',
            onPressed: _canSubmit ? _skipTest : null,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          const SizedBox(height: 16),
          // Di atas kolom-kolomnya, bukan di bawah: dengan tiga kolom,
          // pesan gagal yang ditaruh di bawah terdorong keluar layar
          // justru saat paling perlu dibaca.
          if (_error != null) ...[
            _ErrorNotice(message: _error!),
            const SizedBox(height: 16),
          ],
          _ConfigField(
            fieldKey: ApiConfigPage.fieldKey,
            label: 'Alamat Server',
            hint: '192.168.1.10:8080',
            controller: _controller,
            enabled: !_testing,
            keyboardType: TextInputType.url,
            // Mengetik ulang setelah gagal menghapus pesan lamanya, dan
            // memperbarui pratinjau alamat di bawah kolom.
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 8),
          _ResolvedHint(typed: _typed),
          const SizedBox(height: 20),
          _ConfigField(
            fieldKey: ApiConfigPage.clientIdKey,
            label: 'Client ID',
            hint: 'edge',
            controller: _clientId,
            enabled: !_testing,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 20),
          _ConfigField(
            fieldKey: ApiConfigPage.secretKey,
            label: 'Secret Key',
            hint: '••••••••',
            controller: _secret,
            enabled: !_testing,
            obscure: !_secretVisible,
            onVisibilityToggled: () =>
                setState(() => _secretVisible = !_secretVisible),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Disimpan terenkripsi di perangkat, bukan sebagai teks '
            'biasa.',
            style: AppTheme.pageSubtitle,
          ),
        ],
      ),
    );
  }
}

/// Satu kolom konfigurasi, mengikuti gaya kartu halaman lain: putih,
/// radius 12, garis tepi tipis yang membiru saat difokus.
class _ConfigField extends StatelessWidget {
  const _ConfigField({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
    this.keyboardType,
    this.obscure = false,
    this.onVisibilityToggled,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final TextInputType? keyboardType;

  /// Isinya disembunyikan. Hanya dipakai secret key.
  final bool obscure;

  /// Ada berarti kolomnya bisa dibuka-tutup lewat ikon mata.
  final VoidCallback? onVisibilityToggled;

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.cardTitle),
        const SizedBox(height: 8),
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.value,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: onVisibilityToggled == null
                ? null
                : IconButton(
                    onPressed: enabled ? onVisibilityToggled : null,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.mutedLabel,
                    ),
                  ),
            hintStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.mutedLabel,
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: _border(AppColors.borderAlt),
            enabledBorder: _border(AppColors.borderAlt),
            disabledBorder: _border(AppColors.borderAlt),
            focusedBorder: _border(AppColors.pinActiveBorder),
          ),
        ),
      ],
    );
  }
}

/// Menampilkan alamat yang benar-benar akan ditembak.
///
/// Yang diketik hampir tidak pernah sama dengan yang dipakai — skema
/// ditambahkan, garis miring dibuang, dan path `/list-chargerbox`
/// menempel di belakang. Menampilkannya membuat salah ketik ketahuan sebelum
/// tombol ditekan, termasuk saat `/api` lupa disertakan.
class _ResolvedHint extends StatelessWidget {
  const _ResolvedHint({required this.typed});

  final String typed;

  @override
  Widget build(BuildContext context) {
    if (typed.isEmpty) {
      return const Text(
        'Skema boleh dilewati — alamat tanpa skema dianggap http.',
        style: AppTheme.pageSubtitle,
      );
    }

    return Text(
      'Akan memanggil ${Host.normalizeBaseUrl(typed)}/list-chargerbox',
      style: AppTheme.pageSubtitle,
    );
  }
}

/// Pita merah muda sebagai pasangan [NoticeBar] untuk kabar buruk.
class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.unavailableBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.unavailableFg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.unavailableFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
