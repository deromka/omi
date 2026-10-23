import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/services/devices/connectors/omi_connection.dart';
import 'package:omi/services/devices/models.dart';
import 'package:omi/services/devices/ring_protocol.dart';
import 'package:omi/services/devices/transports/device_transport.dart';
import 'package:omi/utils/debug_log_manager.dart';

class _Documents extends PathProviderPlatform {
  _Documents(this.path);

  final String path;

  @override
  Future<String> getApplicationDocumentsPath() async => path;
}

/// Answers CMD_RING_INFO with [reply] instead of an INFO notification.
class _RingTransport extends DeviceTransport {
  _RingTransport(this.reply);

  final List<int>? reply;
  final _storage = StreamController<List<int>>.broadcast();

  @override
  String get deviceId => 'omi-1';

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<bool> ping() async => true;

  @override
  Stream<List<int>> getCharacteristicStream(String serviceUuid, String characteristicUuid) =>
      characteristicUuid == storageDataStreamCharacteristicUuid ? _storage.stream : const Stream.empty();

  @override
  Future<List<int>> readCharacteristic(String serviceUuid, String characteristicUuid) async => [];

  @override
  Future<void> writeCharacteristic(String serviceUuid, String characteristicUuid, List<int> data) async {
    final r = reply;
    if (characteristicUuid == storageDataStreamCharacteristicUuid && data.first == RingProtocol.cmdInfo && r != null) {
      scheduleMicrotask(() => _storage.add(r));
    }
  }

  @override
  Stream<DeviceTransportState> get connectionStateStream => const Stream.empty();

  @override
  Future<void> dispose() async => _storage.close();
}

Future<List<Map<String, dynamic>>> _warnings() async {
  final file = (await DebugLogManager.getLogFile())!;
  return [
    for (final line in await file.readAsLines())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ].where((e) => e['level'] == 'WARN' || e['level'] == 'WARNING').toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform previousProvider;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('ring-info-diag-');
    previousProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(directory.path);
    SharedPreferences.setMockInitialValues({'devLogsToFileEnabled': true});
    await SharedPreferencesUtil.init();
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousProvider;
    await directory.delete(recursive: true);
  });

  setUp(() async => DebugLogManager.clear());

  BtDevice device() => BtDevice(id: 'omi-1', name: 'Omi', type: DeviceType.omi, rssi: -40);

  test('an INFO answered by an ACK records the ACK status', () async {
    // On 23 Oct every sync stopped on an unanswered INFO and a pendant
    // restart cleared it, with nothing recorded about what the pendant sent.
    final transport = _RingTransport([RingProtocol.notifyAck, 3]);
    final connection = OmiDeviceConnection(device(), transport);

    expect(await connection.getRingInfo(), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final logged = await _warnings();
    expect(logged.map((e) => e['message']), contains('ring_info_unanswered'));
    final entry = logged.firstWhere((e) => e['message'] == 'ring_info_unanswered');
    expect(jsonEncode(entry), contains('ack:3'));
    await transport.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('an INFO met with silence records that nothing arrived', () async {
    final transport = _RingTransport(null);
    final connection = OmiDeviceConnection(device(), transport);

    expect(await connection.getRingInfo(), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final entry = (await _warnings()).firstWhere((e) => e['message'] == 'ring_info_unanswered');
    expect(jsonEncode(entry), contains('"heard":""'));
    await transport.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
