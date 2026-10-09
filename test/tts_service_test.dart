import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];

  Future<void> notify(String method) async {
    final reply = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) => reply.complete(),
        );
    await reply.future;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 1;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Windows waits in Dart and stopping before speech does not call native stop', () async {
    final service = TtsService();
    await service.init();
    expect(
      calls.singleWhere((call) => call.method == 'awaitSpeakCompletion').arguments,
      false,
    );
    await service.stop();
    expect(calls.where((call) => call.method == 'stop'), isEmpty);
  });

  test('another TTS service does not replace the active completion callback', () async {
    final first = TtsService();
    final speech = first.speak('hello');
    await Future<void>.delayed(Duration.zero);
    TtsService();
    await notify('speak.onComplete');
    expect(await speech, true);
  });

  test('hanging up during speech cancels the wait and stops only once', () async {
    final service = TtsService();
    final speech = service.speak('hello');
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    await service.dispose();
    expect(await speech, false);
    expect(calls.where((call) => call.method == 'stop'), hasLength(1));
  });
}
