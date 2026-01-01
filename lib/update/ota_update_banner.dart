import 'package:flutter/material.dart';
import 'ota_update.dart';

class OtaUpdateBanner extends StatelessWidget {
  final OtaUpdateController controller;

  const OtaUpdateBanner({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final st = controller.state;
        if (st == null) return const SizedBox.shrink();
        if (!st.updateAvailable) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;

        final effective = st.effectiveAvailableVersion;

        // Only show "Install" if:
        // - there is a downloaded APK
        // - it's newer than what's installed
        // - it's for current network-latest (or newer fallback)
        // - integrityOk (sha1 matches if provided)
        final canInstallCached = st.downloadedPath != null &&
            st.cachedApkVersion != null &&
            st.integrityOk &&
            compareAppVersions(st.cachedApkVersion!, st.currentVersion) > 0 &&
            compareAppVersions(st.cachedApkVersion!, st.latest.version) >= 0;

        return Card(
          color: cs.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your app has a new update!',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Installed: ${st.currentVersion}  •  Available: $effective',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (canInstallCached && st.cachedApkVersion != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Cached update ready to install.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (st.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    st.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
                if (st.downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: st.progress.clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text(
                    '${(st.progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (canInstallCached) ...[
                      FilledButton.icon(
                        onPressed: st.downloading ? null : () => controller.installDownloaded(),
                        icon: const Icon(Icons.install_mobile_rounded),
                        label: const Text('Install'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: st.downloading ? null : () => controller.downloadLatest(),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Retry download'),
                      ),
                    ] else ...[
                      // If not installable (no download yet OR sha1 mismatch), offer download/retry download.
                      FilledButton.icon(
                        onPressed: st.downloading ? null : () => controller.downloadLatest(),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(st.error != null ? 'Retry download' : 'Download'),
                      ),
                    ],

                    // Keep a lightweight "check again" button as before.
                    FilledButton.tonalIcon(
                      onPressed: st.downloading ? null : () => controller.checkNow(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
