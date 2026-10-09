import 'package:http/http.dart' as http;

/// 非 Web 平台：默认 http.Client 已支持流式响应
http.Client createWebClient() => http.Client();
