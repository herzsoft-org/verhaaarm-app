import 'package:flutter/material.dart';
import 'ota_update.dart';

class OtaUpdateBanner extends StatelessWidget {
  final OtaUpdateController controller;

  const OtaUpdateBanner({super.key, required this.controller});

  String _formatVersionUi(String v) {
    final p = VersionParts.parse(v);
    final core = '${p.major}.${p.minor}.${p.patch}';
    final b = p.build;
    return (b == null) ? core : '$core (Build $b)';
  }

  Future<bool> _confirmRedownload(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erneut herunterladen?'),
        content: const Text(
          'Bist du sicher, dass du die Update-Datei erneut herunterladen willst? '
              'Die vorhandene Datei wird dabei ersetzt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Erneut herunterladen'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

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

        // UI state machine:
        // 1) downloading -> progress only
        // 2) sha1 mismatch / error after download -> error + Redownload button
        // 3) downloaded & verified -> Install button + small redownload icon (with confirm)
        // 4) update available, not downloaded -> Download button
        final showRedownloadOnly = (st.error != null) && !canInstallCached && !st.downloading;

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
                        'Für deine App ist ein neues Update verfügbar!',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Installiert: ${_formatVersionUi(st.currentVersion)}  •  Verfügbar: ${_formatVersionUi(effective)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),

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

                if (!st.downloading) ...[
                  const SizedBox(height: 12),

                  // (4) Update available, not downloaded yet -> Download
                  if (!canInstallCached && !showRedownloadOnly)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => controller.downloadLatest(),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Herunterladen'),
                      ),
                    ),

                  // (2) SHA1 mismatch / error -> Redownload (single button)
                  if (showRedownloadOnly)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => controller.downloadLatest(),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Erneut herunterladen'),
                      ),
                    ),

                  // (3) Downloaded & verified -> Install + small redownload icon (confirm)
                  if (canInstallCached)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => controller.installDownloaded(),
                            icon: const Icon(Icons.install_mobile_rounded),
                            label: const Text('Installieren'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Erneut herunterladen',
                          onPressed: () async {
                            final ok = await _confirmRedownload(context);
                            if (!ok) return;
                            controller.downloadLatest();
                          },
                          icon: const Icon(Icons.restart_alt_rounded),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
