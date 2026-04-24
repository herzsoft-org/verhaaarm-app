import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

class SchnupfspruchButton extends StatefulWidget {
  const SchnupfspruchButton({super.key});

  @override
  State<SchnupfspruchButton> createState() => _SchnupfspruchButtonState();
}

class _SchnupfspruchButtonState extends State<SchnupfspruchButton> {
  static const _iconAsset = 'assets/icons/moustache.svg';
  static const _jsonAsset = 'assets/data/schnupfsprueche.json';

  final Random _random = Random();

  List<_Schnupfspruch>? _cached;

  Future<List<_Schnupfspruch>> _loadSchnupfsprueche() async {
    final cached = _cached;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_jsonAsset);
    final decoded = jsonDecode(raw);

    final list = (decoded as List)
        .map((e) => _Schnupfspruch.fromJson((e as Map).cast<String, dynamic>()))
        .where((e) => e.title.trim().isNotEmpty || e.text.trim().isNotEmpty)
        .toList(growable: false);

    _cached = list;
    return list;
  }

  _Schnupfspruch _randomSchnupfspruch(List<_Schnupfspruch> list) {
    return list[_random.nextInt(list.length)];
  }

  Future<void> _openDialog() async {
    List<_Schnupfspruch> list;

    try {
      list = await _loadSchnupfsprueche();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schnupfsprüche konnten nicht geladen werden.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Schnupfsprüche gefunden.')),
      );
      return;
    }

    var current = _randomSchnupfspruch(list);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final theme = Theme.of(ctx);
            final colorScheme = theme.colorScheme;

            return AlertDialog(
              title: Row(
                children: [
                  SvgPicture.asset(
                    _iconAsset,
                    width: 28,
                    height: 28,
                    colorFilter: ColorFilter.mode(
                      colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: SelectableText(
                    current.text,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        setStateDialog(() {
                          if (list.length == 1) {
                            current = list.first;
                            return;
                          }

                          var next = _randomSchnupfspruch(list);
                          while (next == current) {
                            next = _randomSchnupfspruch(list);
                          }
                          current = next;
                        });
                      },
                      icon: const Icon(Icons.casino_rounded),
                      label: const Text('Noch einer'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Schließen'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Schnupfspruch',
      icon: SvgPicture.asset(
        _iconAsset,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
          BlendMode.srcIn,
        ),
      ),
      onPressed: _openDialog,
    );
  }
}

class _Schnupfspruch {
  final String title;
  final String text;

  const _Schnupfspruch({
    required this.title,
    required this.text,
  });

  factory _Schnupfspruch.fromJson(Map<String, dynamic> json) {
    return _Schnupfspruch(
      title: (json['title'] as String?)?.trim() ?? 'Schnupfspruch',
      text: (json['text'] as String?)?.trim() ?? '',
    );
  }
}