import 'package:flutter_test/flutter_test.dart';
import 'package:jamiipay/src/data/wallet_key_backup_codec.dart';

void main() {
  group('WalletKeyBackupCodec v1 (legacy)', () {
    test('decodes a v1 payload', () {
      const raw =
          '{"v":1,"addr":"0xabc","s":"aa","n":"bb","c":"cc"}';
      final backup = WalletKeyBackupCodec.decode(raw);
      expect(backup.addressHex, '0xabc');
      expect(backup.saltHex, 'aa');
    });

    test('rejects garbage', () {
      expect(
        () => WalletKeyBackupCodec.decode('not json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => WalletKeyBackupCodec.decode('{"v":99}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('v2 payload through v1 decode asks for app update, not silent fail',
        () {
      const v2 =
          '{"v":2,"id":"b-id","addr":"0xabc","s":"aa","n":"bb","c":"cc"}';
      expect(
        () => WalletKeyBackupCodec.decode(v2),
        throwsA(predicate<FormatException>(
            (e) => e.message.contains('newer split backup'))),
      );
    });
  });

  group('SplitBackupEnvelope v2', () {
    test('decodes a v2 envelope', () {
      const raw =
          '{"v":2,"id":"backup-1","addr":"0xabc","s":"aa","n":"bb","c":"cc"}';
      final env = SplitBackupEnvelope.decodeV2(raw);
      expect(env.backupId, 'backup-1');
      expect(env.addressHex, '0xabc');
      expect(env.ciphertextHex, 'cc');
    });

    test('rejects v1 and garbage as non-v2', () {
      expect(
        () => SplitBackupEnvelope.decodeV2('{"v":1,"addr":"x"}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SplitBackupEnvelope.decodeV2('hello'),
        throwsA(isA<FormatException>()),
      );
    });

    test('encodeV2 is verbatim (bridge owns the envelope shape)', () {
      const envelope = '{"v":2,"id":"x"}';
      expect(WalletKeyBackupCodec.encodeV2(envelope), envelope);
    });
  });

  group('BackupInfo.inspect', () {
    test('identifies v1 legacy backups', () {
      const raw =
          '{"v":1,"addr":"0xabc","s":"aa","n":"bb","c":"cc"}';
      final info = WalletKeyBackupCodec.inspect(raw);
      expect(info.version, 1);
      expect(info.isLegacy, isTrue);
      expect(info.addressHex, '0xabc');
      expect(info.backupId, isNull);
      expect(info.label, 'v1 legacy backup');
    });

    test('identifies v2 split backups with id', () {
      const raw =
          '{"v":2,"id":"backup-1","addr":"0xabc","s":"aa","n":"bb","c":"cc"}';
      final info = WalletKeyBackupCodec.inspect(raw);
      expect(info.version, 2);
      expect(info.isLegacy, isFalse);
      expect(info.backupId, 'backup-1');
      expect(info.label, 'v2 split backup');
    });

    test('rejects non-backup QRs', () {
      expect(
        () => WalletKeyBackupCodec.inspect('hello'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => WalletKeyBackupCodec.inspect('{"v":99,"addr":"x"}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => WalletKeyBackupCodec.inspect('{"v":2,"addr":"x"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
