import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../slide_pipeline/slide_repo.dart';

class EndSummaryPage extends StatefulWidget {
  const EndSummaryPage({
    super.key,
    required this.slideContexts,
  });

  final List<SlideSummaryContext> slideContexts;

  @override
  State<EndSummaryPage> createState() => _EndSummaryPageState();
}

class _EndSummaryPageState extends State<EndSummaryPage> {
  final FlutterTts _flutterTts = FlutterTts();
  String _overallSummary = '';
  bool _isGeneratingOverall = false;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _generateOverallSummary();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _generateOverallSummary() async {
    if (widget.slideContexts.isEmpty) {
      setState(() {
        _overallSummary = 'No slides captured during this session.';
      });
      return;
    }

    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _overallSummary =
            'Unable to generate overall summary because GEMINI_API_KEY is not configured.';
      });
      return;
    }

    setState(() {
      _isGeneratingOverall = true;
    });

    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash-exp',
        apiKey: apiKey,
      );

      final slidesText = widget.slideContexts
          .asMap()
          .entries
          .map((entry) {
        final context = entry.value;
        final shortSummary = _getShortSummary(context.summary);
        final slideLabel = context.slideNumber != null
            ? 'Slide ${context.slideNumber}'
            : 'Slide ${entry.key + 1}';
        return '$slideLabel: $shortSummary';
      }).join('\n\n');

      final prompt = '''
You are summarizing a presentation. Below are summaries of individual slides.
Create a cohesive overall summary that captures the main themes and key points of the entire presentation.
Keep it concise (2-3 sentences).

Slide Summaries:
$slidesText

Overall Summary:
''';

      final response = await model.generateContent([Content.text(prompt)]);

      setState(() {
        _overallSummary =
            response.text?.trim() ?? 'Unable to generate overall summary.';
        _isGeneratingOverall = false;
      });
    } catch (error) {
      debugPrint('Error generating overall summary: $error');
      setState(() {
        _overallSummary = 'Error generating summary.';
        _isGeneratingOverall = false;
      });
    }
  }

  List<String> _extractSummaryList(Map<String, dynamic> summary) {
    final candidates = [
      summary['end_summary'],
      summary['summary'],
      summary['display_summary'],
    ];

    for (final candidate in candidates) {
      if (candidate is List && candidate.isNotEmpty) {
        return candidate.map((item) => item.toString()).toList();
      }
      if (candidate is String && candidate.trim().isNotEmpty) {
        return [candidate.trim()];
      }
    }

    // Fall back to combining title/enumeration when explicit summary is missing.
    final titleList = summary['title'];
    if (titleList is List && titleList.isNotEmpty) {
      return [titleList.first.toString()];
    }
    final enumeration = summary['enumeration'];
    if (enumeration is List && enumeration.isNotEmpty) {
      return [
        enumeration.take(3).map((item) => item.toString()).join('; '),
      ];
    }

    return [];
  }

  String _getShortSummary(Map<String, dynamic> summary) {
    final lines = _extractSummaryList(summary);
    if (lines.isNotEmpty) {
      return lines.first;
    }
    return 'No summary available';
  }

  Future<void> _speakSummary() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
      });
      return;
    }

    setState(() {
      _isSpeaking = true;
    });

    final summaries = widget.slideContexts
        .asMap()
        .entries
        .map((entry) {
      final context = entry.value;
      final label = context.slideNumber != null
          ? 'Slide ${context.slideNumber}'
          : 'Slide ${entry.key + 1}';
      return '$label: ${_getShortSummary(context.summary)}';
    }).join('. ');

    final fullText = [
      summaries,
      if (_overallSummary.isNotEmpty) 'Overall Summary: $_overallSummary',
    ].where((segment) => segment.trim().isNotEmpty).join('. ');

    if (fullText.isEmpty) {
      setState(() {
        _isSpeaking = false;
      });
      return;
    }

    await _flutterTts.speak(fullText);

    setState(() {
      _isSpeaking = false;
    });
  }

  Future<void> _copySummaryToClipboard() async {
    final summaries = widget.slideContexts
        .asMap()
        .entries
        .map((entry) {
      final context = entry.value;
      final label = context.slideNumber != null
          ? 'Slide ${context.slideNumber}'
          : 'Slide ${entry.key + 1}';
      return {
        'slide': label,
        'summary': _extractSummaryList(context.summary),
        'raw': context.summary,
        'captured_at': context.capturedAt.toIso8601String(),
      };
    }).toList();

    final payload = jsonEncode({
      'slides': summaries,
      'overall_summary': _overallSummary,
    });

    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session summary copied to clipboard.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.slideContexts;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Session Summary'),
        actions: [
          IconButton(
            tooltip: 'Copy summary JSON',
            onPressed: history.isEmpty ? null : _copySummaryToClipboard,
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (history.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No slide summaries captured yet.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                else
                  ...history.asMap().entries.map((entry) {
                    final index = entry.key;
                    final context = entry.value;
                    final label = context.slideNumber != null
                        ? 'Slide ${context.slideNumber}'
                        : 'Slide ${index + 1}';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _getShortSummary(context.summary),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Overall Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _isGeneratingOverall
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Generating overall summary…'),
                                  ],
                                ),
                              )
                            : Text(
                                _overallSummary,
                                style: const TextStyle(fontSize: 14),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                top: BorderSide(color: Colors.grey[300]!, width: 2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: history.isEmpty ? null : _speakSummary,
                    icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
                    label: Text(_isSpeaking ? 'Stop Speech' : 'Play Audio Summary'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.home),
                    label: const Text('Back to Home'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

