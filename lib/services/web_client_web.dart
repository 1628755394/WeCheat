import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Web 平台：XHR 无法流式读响应体，fetch API 才行
http.Client createWebClient() => FetchClient(mode: RequestMode.cors);
