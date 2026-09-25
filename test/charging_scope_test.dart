import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charging_scope.dart';

/// Melaporkan apakah ChargingScope terlihat dari posisinya di pohon.
class _Probe extends StatelessWidget {
  const _Probe(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final found = ChargingScope.maybeOf(context) != null;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ${found ? 'ADA' : 'TIDAK ADA'}'),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _Probe('pushed')),
              ),
              child: const Text('buka'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('scope di atas MaterialApp terlihat dari rute yang di-push', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChargingScope(child: const MaterialApp(home: _Probe('home'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('home: ADA'), findsOneWidget);

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    expect(find.text('pushed: ADA'), findsOneWidget);
  });

  testWidgets('scope sebagai home: TIDAK terlihat dari rute yang di-push — '
      'inilah sebab /start pernah tidak terkirim', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ChargingScope(child: const _Probe('home'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('home: ADA'), findsOneWidget);

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    // Rute baru disisipkan sejajar dengan `home` di bawah Navigator,
    // bukan sebagai turunannya.
    expect(find.text('pushed: TIDAK ADA'), findsOneWidget);
  });

  testWidgets('SPKLUApp memasang scope sehingga rute lanjutan melihatnya', (
    tester,
  ) async {
    late BuildContext pushedContext;

    await tester.pumpWidget(
      ChargingScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (inner) {
                    pushedContext = inner;
                    return const SizedBox();
                  },
                ),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    final scope = ChargingScope.maybeOf(pushedContext);
    expect(scope, isNotNull);
    expect(scope!.repository, isNotNull);
  });
}
