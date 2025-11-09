import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/env.dart';

class FastApiClient {
  FastApiClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _baseUri = Uri.parse(baseUrl ?? Env.fastApiBaseUrl);

  final http.Client _http;
  final Uri _baseUri;

  Future<http.Response> postImage({
    required String path,
    required Uint8List imageBytes,
    String fieldName = 'image',
    String contentType = 'image/jpeg',
  }) async {
    final uri = _baseUri.resolve(path);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          imageBytes,
          filename: 'frame_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType.parse(contentType),
        ),
      );

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  Future<http.Response> postImages({
    required String path,
    required Map<String, Uint8List> images,
    String contentType = 'image/jpeg',
  }) async {
    final uri = _baseUri.resolve(path);
    final request = http.MultipartRequest('POST', uri);
    final mediaType = MediaType.parse(contentType);

    images.forEach((fieldName, bytes) {
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: '${fieldName}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: mediaType,
        ),
      );
    });

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  void dispose() {
    _http.close();
  }
}
