import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/host.dart';
import '../data/charging_scope.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';
import 'charge_box_page.dart';

/// Halaman pembuka: alamat edge controller diisi di sini sebelum
/// aplikasi menyentuh backend.
///
/// Controller kerap berpindah IP dan dipasang di jaringan lokal tanpa
/// nama domain, jadi alamatnya harus bisa diatur di lapangan. Yang
/// diketik boleh sependek `192.168.1.10:8080` — [Host.normalizeBaseUrl]
/// melengkapinya menjadi `http://192.168.1.10:8080`.
///
/// Alamat baru dipakai langsung, tetapi baru disimpan setelah terbukti
/// bisa dihubungi, supaya alamat salah ketik tidak ikut teringat.
class ApiConfigPage extends StatefulWidget {
  const ApiConfigPage({super.key});

  /// Key kolom alamat, dipakai test.
  static const fieldKey = Key('api-base-url-field');

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage> {
  late final TextEditingController _controller = TextEditingController(
    text: ApiConfig.baseUrl,
  );

  bool _testing = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _typed => _controller.text.trim();

  bool get _canSubmit => _typed.isNotEmpty && !_testing;

  /// Memasang alamat, memastikan bisa dihubungi, lalu masuk ke daftar
  /// charge box.
  ///
  /// Ujinya memakai `GET /list` — endpoint yang juga dipakai halaman
  /// berikutnya, jadi kalau lolos di sini halaman itu pasti jalan.
  Future<void> _connect() async {
    if (!_canSubmit) return;

    FocusScope.of(context).unfocus();
    final repository = ChargingScope.maybeOf(context)?.repository;

    setState(() {
      _testing = true;
      _error = null;
    });

    ApiConfig.apply(_typed, client: repository?.client);
    debugPrint('[CONFIG] Menguji koneksi ke ${ApiConfig.baseUrl}/list');

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
    ApiConfig.apply(
      _typed,
      client: ChargingScope.maybeOf(context)?.repository.client,
    );
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ChargeBoxPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Konfigurasi Server',
      subtitle: 'Masukkan alamat edge controller yang akan dipakai '
          'aplikasi ini.',
      // Halaman paling awal — tidak ada tempat untuk pulang.
      isHome: true,
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
          const SizedBox(height: 32),
          _AddressField(
            controller: _controller,
            enabled: !_testing,
            // Mengetik ulang setelah gagal menghapus pesan lamanya, dan
            // memperbarui pratinjau alamat di bawah kolom.
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 8),
          _ResolvedHint(typed: _typed),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorNotice(message: _error!),
          ],
        ],
      ),
    );
  }
}

/// Kolom alamat, mengikuti gaya kartu halaman lain: putih, radius 12,
/// garis tepi tipis yang membiru saat difokus.
class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Alamat Server', style: AppTheme.cardTitle),
        const SizedBox(height: 8),
        TextField(
          key: ApiConfigPage.fieldKey,
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.value,
          ),
          decoration: InputDecoration(
            hintText: '192.168.1.10:8080',
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
/// ditambahkan, garis miring dibuang, dan path `/list` menempel di
/// belakang. Menampilkannya membuat salah ketik ketahuan sebelum
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
      'Akan memanggil ${Host.normalizeBaseUrl(typed)}/list',
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
