import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/slide_pipeline/slide_repo.dart';

class EndSummaryPage extends StatelessWidget {
  const EndSummaryPage({
    super.key,
    required this.summaries,
  });

  final List<SlideSummaryContext> summaries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('End Summary'),
      ),
      body: summaries.isEmpty
          ? const Center(
              child: Text('No slides captured yet.'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: summaries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                final summaryText = const JsonEncoder.withIndent('  ')
                    .convert(summary.summary);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.slideNumber != null
                              ? 'Slide #${summary.slideNumber}'
                              : 'Slide',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(summary.capturedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          summaryText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final datePart =
        '${local.year.toString().padLeft(4, '0')}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
    final timePart =
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}';
    return '$datePart $timePart';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

