import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:multistockfish/multistockfish.dart';
import 'package:multistockfish/src/bindings.dart';

class _Bindings implements StockfishBindings {
  final commands = <String>[];

  @override
  int init() => 0;

  @override
  int main() => 0;

  @override
  int stdinWrite(String input) {
    commands.add(input);
    return 0;
  }

  @override
  String? stdoutRead() => null;
}

void main() {
  test('failed spawn can be cleaned up before retry', () async {
    await runZoned(
      () async {
        await expectLater(Stockfish.instance.start(), throwsException);
        expect(Stockfish.instance.state.value, StockfishState.error);

        await Stockfish.instance.quit();
        expect(Stockfish.instance.state.value, StockfishState.initial);
      },
      zoneValues: {
        stockfishSpawnIsolatesKey:
            (SendPort _, SendPort _, StockfishFlavor _) async => false,
      },
    );
  });

  test('startup receives a banner sent before isolate spawn returns', () async {
    final bindings = _Bindings();
    SendPort? mainPort;
    SendPort? stdoutPort;

    await runZoned(
      () async {
        try {
          final start = Stockfish.instance.start();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(bindings.commands, contains('uci\n'));
          stdoutPort!.send('uciok');
          await start;
          expect(Stockfish.instance.state.value, StockfishState.ready);
        } finally {
          mainPort?.send(0);
          await Future<void>.delayed(Duration.zero);
        }
      },
      zoneValues: {
        stockfishBindingsFactoryKey: (StockfishFlavor _) => bindings,
        stockfishSpawnIsolatesKey: (
          SendPort enginePort,
          SendPort outputPort,
          StockfishFlavor _,
        ) async {
          mainPort = enginePort;
          stdoutPort = outputPort;
          outputPort.send('Stockfish 16');
          // Deliver output before the spawn Future completes.
          await Future<void>.delayed(Duration.zero);
          return true;
        },
      },
    );
  });

  test('an early native exit cannot become a ready engine', () async {
    await runZoned(
      () async {
        await expectLater(
          Stockfish.instance.start(),
          throwsA(isA<StateError>()),
        );
        expect(Stockfish.instance.state.value, StockfishState.error);
        await Stockfish.instance.quit();
      },
      zoneValues: {
        stockfishSpawnIsolatesKey: (
          SendPort enginePort,
          SendPort outputPort,
          StockfishFlavor _,
        ) async {
          outputPort.send('Stockfish 16');
          enginePort.send(0);
          await Future<void>.delayed(Duration.zero);
          return true;
        },
      },
    );
  });
}
