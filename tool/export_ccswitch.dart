import 'dart:convert';
import 'dart:io';

import 'package:wecheat/services/cc_switch_io.dart';

Future<void> main() async {
  final providers = await loadCcProviders();
  final file = File('web/ccswitch_providers.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert([
      for (final provider in providers)
        {
          'id': provider.id,
          'name': provider.name,
          'appType': provider.appType,
          'baseUrl': provider.baseUrl,
          'apiKey': provider.apiKey,
          'model': provider.model,
          'protocol': provider.protocol,
        },
    ]),
  );
  stdout.writeln('Exported ${providers.length} providers to ${file.path}');
}
