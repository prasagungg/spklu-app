import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/config/host.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('alamat tanpa skema dianggap http', () {
      expect(Host.normalizeBaseUrl('192.168.1.10:8080'),
          'http://192.168.1.10:8080');
      expect(Host.normalizeBaseUrl('10.0.2.2'), 'http://10.0.2.2');
      expect(Host.normalizeBaseUrl('localhost:8080'), 'http://localhost:8080');
    });

    test('skema yang sudah ada dipertahankan', () {
      expect(Host.normalizeBaseUrl('http://host:8080'), 'http://host:8080');
      expect(
        Host.normalizeBaseUrl('https://edge.example.id/api'),
        'https://edge.example.id/api',
      );
    });

    test('garis miring di ujung dibuang agar path tidak jadi //', () {
      expect(Host.normalizeBaseUrl('http://host:8080/'), 'http://host:8080');
      expect(Host.normalizeBaseUrl('https://host/api//'), 'https://host/api');
    });

    test('spasi di ujung diabaikan', () {
      expect(Host.normalizeBaseUrl('  192.168.1.10:8080  '),
          'http://192.168.1.10:8080');
    });

    test('kosong tetap kosong', () {
      expect(Host.normalizeBaseUrl(''), '');
      expect(Host.normalizeBaseUrl('   '), '');
    });
  });

  group('isPrivateHost', () {
    test('rentang jaringan lokal dikenali', () {
      for (final host in [
        'localhost',
        'charger.local',
        '127.0.0.1',
        '10.0.2.2',
        '192.168.1.10',
        '172.16.0.1',
        '172.31.255.254',
        '100.64.0.50', // Tailscale / CGNAT
      ]) {
        expect(Host.isPrivateHost(host), isTrue, reason: host);
      }
    });

    test('host publik tidak dianggap lokal', () {
      for (final host in [
        'edge-controller-playground.lentera-app.id',
        '8.8.8.8',
        '172.32.0.1', // di luar 172.16/12
        '192.169.1.1', // di luar 192.168/16
        '100.128.0.1', // di luar 100.64/10
        '',
      ]) {
        expect(Host.isPrivateHost(host), isFalse, reason: host);
      }
    });

    test('isPrivate menerima alamat apa adanya', () {
      expect(Host.isPrivate('192.168.1.10:8080'), isTrue);
      expect(Host.isPrivate('http://10.0.2.2:8080/api'), isTrue);
      expect(
        Host.isPrivate('https://edge-controller-playground.lentera-app.id/api'),
        isFalse,
      );
    });

    test('oktet tidak valid tidak dianggap lokal', () {
      expect(Host.isPrivateHost('192.168.1'), isFalse);
      expect(Host.isPrivateHost('192.168.1.999'), isFalse);
      expect(Host.isPrivateHost('192.168.a.1'), isFalse);
    });
  });
}
