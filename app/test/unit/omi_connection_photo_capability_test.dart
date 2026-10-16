import 'package:flutter_test/flutter_test.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/services/devices/connectors/omi_connection.dart';
import 'package:omi/services/devices/models.dart';
import 'package:omi/services/devices/transports/device_transport.dart';

/// A characteristic absent from [reads] answers with an empty read, as the
/// native transport does for firmware that does not expose it. Counts every
/// read of the image stream so a test can prove a pendant is never probed.
class _Transport extends DeviceTransport {
  _Transport(this.reads);

  final Map<String, List<int>> reads;
  int imageReads = 0;

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
  Stream<List<int>> getCharacteristicStream(String serviceUuid, String characteristicUuid) => const Stream.empty();

  @override
  Future<List<int>> readCharacteristic(String serviceUuid, String characteristicUuid) async {
    if (characteristicUuid == imageDataStreamCharacteristicUuid) imageReads++;
    return reads[characteristicUuid] ?? [];
  }

  @override
  Future<void> writeCharacteristic(String serviceUuid, String characteristicUuid, List<int> data) async {}

  @override
  Stream<DeviceTransportState> get connectionStateStream => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

BtDevice _device(DeviceType type) => BtDevice(id: 'omi-1', name: 'Omi', type: type, rssi: -40);

void main() {
  group('photo streaming capability', () {
    test('a pendant has no camera and is never probed for one', () async {
      final transport = _Transport({imageDataStreamCharacteristicUuid: [1, 2]});
      final connection = OmiDeviceConnection(_device(DeviceType.omi), transport);

      expect(await connection.hasPhotoStreamingCharacteristic(), isFalse);
      expect(transport.imageReads, 0);
    });

    test('glass whose image characteristic reads empty has no camera', () async {
      final connection = OmiDeviceConnection(_device(DeviceType.openglass), _Transport({}));

      expect(await connection.hasPhotoStreamingCharacteristic(), isFalse);
    });

    test('glass exposing the image characteristic has a camera', () async {
      final connection =
          OmiDeviceConnection(_device(DeviceType.openglass), _Transport({imageDataStreamCharacteristicUuid: [1]}));

      expect(await connection.hasPhotoStreamingCharacteristic(), isTrue);
    });
  });
}
