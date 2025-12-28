import 'package:flutter/material.dart';

import '../../models/dtos.dart';

class QuoteOfTheDayCard extends StatelessWidget {
  final QuoteDto quote;

  const QuoteOfTheDayCard({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_quote_rounded, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Zitate unserer lieben Bbr.',
                  style: tt.titleSmall, // smaller header
                ),
              ],
            ),
            const SizedBox(height: 10),
            RichText(
              text: TextSpan(
                style: tt.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: tt.bodyMedium?.color,
                ),
                children: [
                  TextSpan(text: '„${quote.text}“'),
                  if (quote.author != null && quote.author!.isNotEmpty) ...[
                    const TextSpan(text: ' – '),
                    TextSpan(
                      text: quote.author!,
                      style: tt.bodySmall?.copyWith(
                        fontStyle: FontStyle.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
