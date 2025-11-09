import 'dart:typed_data';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'globals.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<Map<String, dynamic>> get_gemini_response(Uint8List imageBytes) async {
  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: dotenv.env['GEMINI_API_KEY']!,
  );

  final promptPart = TextPart(GET_ALL_PROMPT);
  final imagePart = DataPart('image/png', imageBytes);

  final response = await model.generateContent([
    Content.multi([
      promptPart,
      imagePart,
    ])
  ]);

  String resText = response.text ?? '';

  if (resText.startsWith("```json")) {
    resText = resText.replaceFirst("```json\n", "").replaceFirst("\n```", "");
  }

  final dataDict = Map<String, dynamic>.from(jsonDecode(resText));
  return dataDict;
}