import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sih_voice_bridge/app/services/model_download_service.dart';
import 'package:sih_voice_bridge/app/services/model_manager.dart';
import 'support/model_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late TestCatalog catalog;
  late TestDownloadBridge bridge;
  late ModelDownloadService service;

  ModelDownloadService newService() => ModelDownloadService(
      appDataDirectoryPath: bridge.getAppDataDirectoryPath,
      nativeBridgeService: bridge,
      catalogService: catalog,
      pollInterval: const Duration(milliseconds: 5));
  ModelManager manager(ModelDownloadService downloads) => ModelManager(
      appDataDirectoryPath: bridge.getAppDataDirectoryPath,
      nativeBridgeService: bridge,
      catalogService: catalog,
      downloadService: downloads);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('itantra-model-test-');
    catalog = TestCatalog();
    bridge = TestDownloadBridge(root, catalog);
    service = newService();
  });
  tearDown(() async {
    service.dispose();
    await bridge.dispose();
    await root.delete(recursive: true);
  });

  test('an existing model still downloads its missing tokenizer', () async {
    await writeInternal(root, 'en/stt-en-model.int8.onnx',
        catalog.files['stt-en-model.int8.onnx']!);
    expect(await service.isModelDownloaded('en'), isFalse);
    await service.downloadModel(model: catalog.models['en']!);
    expect(await service.isModelDownloaded('en'), isTrue);
    expect(bridge.starts['en'], isNull);
    expect(bridge.starts['tokens_en'], 1);
  });

  test('partial final files and abandoned part files never count as ready',
      () async {
    await writeInternal(root, 'en/stt-en-model.int8.onnx', [1, 2, 3]);
    await writeInternal(root, 'en/stt-en-model.int8.onnx.part',
        catalog.files['stt-en-model.int8.onnx']!);
    expect(await service.isModelDownloaded('en'), isFalse);
    await service.downloadModel(model: catalog.models['en']!);
    expect(await service.isModelDownloaded('en'), isTrue);
    expect(
        await File('${root.path}/stt_models/en/stt-en-model.int8.onnx.part')
            .exists(),
        isFalse);
    expect(await File((await service.getModelPath('en'))!).readAsBytes(),
        catalog.files['stt-en-model.int8.onnx']);
  });

  test('same-size corruption is rejected and native record reset for retry',
      () async {
    bridge.corrupt = true;
    await expectLater(
        service.downloadModel(model: catalog.models['en']!), throwsStateError);
    expect(bridge.cancelled, contains('en'));
    expect(
        await File('${root.path}/stt_models/en/stt-en-model.int8.onnx')
            .exists(),
        isFalse);
    bridge.corrupt = false;
    await service.downloadModel(model: catalog.models['en']!);
    expect(await service.isModelDownloaded('en'), isTrue);
    expect(bridge.starts['en'], 2);
  });

  test('sequential Indic downloads share one verified tokenizer', () async {
    final models = manager(service);
    addTearDown(models.dispose);
    await models.downloadSelection(['hi', 'gu']);
    expect(models.downloadedLanguages, containsAll(['hi', 'gu']));
    expect(bridge.starts['tokens_indic'], 1);
    expect(bridge.startOrder, ['hi', 'tokens_indic', 'gu']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(ModelManager.selectionKey), ['hi', 'gu']);
    expect(prefs.getBool(ModelManager.pendingKey), isTrue);
    await models.markSetupComplete();
    expect(prefs.getBool(ModelManager.pendingKey), isFalse);
  });

  test(
      'recreation restores saved progress and continues the existing ID and queue',
      () async {
    SharedPreferences.setMockInitialValues({
      ModelManager.selectionKey: ['en', 'hi'],
      ModelManager.pendingKey: true,
    });
    bridge.states['en'] = {
      'downloadId': 77,
      'status': 'running',
      'bytesDownloaded': 40,
      'totalBytes': 100
    };
    final models = manager(service);
    addTearDown(models.dispose);
    await models.initialize();
    expect(models.selectedLanguages, ['en', 'hi']);
    expect(models.progressFor('en'), closeTo(0.396, 0.0001));
    expect(models.activeLanguage, 'en');
    final work = models.downloadSelection(models.selectedLanguages);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await models.initialize();
    expect(models.progressFor('en'), closeTo(0.396, 0.0001));
    await bridge.complete('en', 'stt-en-model.int8.onnx');
    await work;
    expect(bridge.states['en']!['downloadId'], 77);
    expect(bridge.starts['en'], isNull);
    expect(models.downloadedLanguages, containsAll(['en', 'hi']));
    expect(models.progressFor('hi'), 1);
  });

  test('later initialize calls reconcile completion while app was backgrounded',
      () async {
    final models = manager(service);
    addTearDown(models.dispose);
    await models.initialize();
    expect(models.downloadedLanguages, isEmpty);
    await bridge.complete('en', 'stt-en-model.int8.onnx');
    await bridge.complete('tokens_en', 'stt-en-tokens.txt');
    await models.initialize();
    expect(models.downloadedLanguages, ['en']);
  });

  test(
      'queue survives observer disposal without cancelling the native transfer',
      () async {
    bridge.hold = true;
    final models = manager(service);
    final work = models.downloadSelection(['en', 'hi']);
    final expectation = expectLater(work, throwsStateError);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!bridge.states.containsKey('en')) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Native download did not start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(ModelManager.selectionKey), ['en', 'hi']);
    models.dispose();
    await expectation;
    expect(bridge.cancelled, isEmpty);
    expect(bridge.states['en']!['status'], 'running');
  });

  test('failed Android downloads can be retried', () async {
    bridge.states['en'] = {'downloadId': 2, 'status': 'failed', 'reason': 1006};
    await expectLater(
        service.downloadModel(model: catalog.models['en']!), throwsStateError);
    expect(bridge.cancelled, contains('en'));
    await service.downloadModel(model: catalog.models['en']!);
    expect(await service.isModelDownloaded('en'), isTrue);
  });

  test('more than two languages are rejected before downloading', () async {
    final models = manager(service);
    addTearDown(models.dispose);
    await expectLater(
        models.downloadSelection(['en', 'hi', 'gu']), throwsStateError);
    expect(bridge.starts, isEmpty);
  });
}
