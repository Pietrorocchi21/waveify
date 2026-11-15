import 'package:dio/dio.dart';

/// Minimal placeholder for a catalog client.
class VisitorSession {
  Future<String> getVisitorData() async => '';
}

class InnertubeClient {
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body, {
    String? visitorData,
    CancelToken? cancelToken,
  }) async {
    return <String, dynamic>{
      'endpoint': endpoint,
      'body': body,
      'visitorData': ?visitorData,
    };
  }
}
