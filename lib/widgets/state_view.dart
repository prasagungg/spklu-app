import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Tampilan pengganti isi halaman saat sedang memuat, kosong, atau gagal.
/// Selalu bisa digulir agar tetap kompatibel dengan pull-to-refresh.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Muat Ulang',
  });

  const StateView.loading({super.key})
    : icon = null,
      title = 'Memuat charge box…',
      message = 'Mengambil daftar charger yang sedang terhubung.',
      onRetry = null,
      retryLabel = '';

  /// Null menggantinya dengan spinner.
  final IconData? icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: AppColors.connectorIconGradient,
                        shape: BoxShape.circle,
                      ),
                      child: icon == null
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.primary,
                              ),
                            )
                          : Icon(icon, size: 32, color: AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTheme.cardTitle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppTheme.pageSubtitle,
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 18),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        label: Text(
                          retryLabel,
                          style: AppTheme.buttonLabel.copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
