import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class EndSummaryPage extends StatefulWidget {
  final List<Map<String, dynamic>> slideSummaries;

  const EndSummaryPage({super.key, required this.slideSummaries});

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
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _generateOverallSummary() async {
    setState(() {
      _isGeneratingOverall = true;
    });

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY']!;
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      final slidesText = widget.slideSummaries
          .asMap()
          .entries
          .map((entry) {
        final shortSummary = entry.value['end_summary'];
        if (shortSummary != null && shortSummary is List && shortSummary.isNotEmpty) {
          return 'Slide ${entry.key + 1}: ${shortSummary[0]}';
        }
        return 'Slide ${entry.key + 1}: No summary';
      })
          .join('\n\n');

      final prompt = '''
You are summarizing a presentation. Below are summaries of individual slides.
Create a cohesive overall summary that captures the main themes and key points of the entire presentation.
Keep it concise (2-3 sentences).

Slide Summaries:
$slidesText

Overall Summary:
''';

      final response = await model.generateContent([
        Content.text(prompt)
      ]);

      setState(() {
        _overallSummary = response.text ?? 'Unable to generate overall summary.';
        _isGeneratingOverall = false;
      });
    } catch (e) {
      print('Error generating overall summary: $e');
      String errorMessage = 'Error generating summary.';
      
      // Check if it's a quota error
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('quota') || errorString.contains('limit')) {
        errorMessage = 'API quota exceeded. Please try again later.';
      } else if (errorString.contains('network') || errorString.contains('connection')) {
        errorMessage = 'Network error. Please check your connection and try again.';
      }
      
      setState(() {
        _overallSummary = errorMessage;
        _isGeneratingOverall = false;
      });
    }
  }

  String _getShortSummary(Map<String, dynamic> slide) {
    final shortSummary = slide['end_summary'];
    if (shortSummary != null && shortSummary is List && shortSummary.isNotEmpty) {
      return shortSummary[0].toString();
    }
    return 'No summary available';
  }

  Future<void> _speakSummary() async {
    setState(() {
      _isSpeaking = true;
    });

    final summaries = widget.slideSummaries
        .asMap()
        .entries
        .map((entry) => 'Slide ${entry.key + 1}: ${_getShortSummary(entry.value)}')
        .join('. ');

    final fullText = '$summaries. Overall Summary: $_overallSummary';

    await _flutterTts.speak(fullText);

    setState(() {
      _isSpeaking = false;
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Session Summary'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...widget.slideSummaries.asMap().entries.map((entry) {
                  final index = entry.key;
                  final slide = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Slide ${index + 1}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getShortSummary(slide),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
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
                            ? const CircularProgressIndicator()
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
              border: Border(top: BorderSide(color: Colors.grey[300]!, width: 2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSpeaking ? null : _speakSummary,
                    icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
                    label: Text(_isSpeaking ? 'Speaking...' : 'Play Audio Summary'),
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