import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_photo_kit/native_photo_kit.dart';

void main() => runApp(const MaterialApp(home: ExamplePage()));

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  Uint8List? _result;
  String _status = 'Pick an operation';

  Future<String> _sample(String name) async {
    final data = await rootBundle.load('assets/$name');
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  Future<void> _run(String label, Future<Uint8List?> Function() operation) async {
    final watch = Stopwatch()..start();
    try {
      final bytes = await operation();
      setState(() {
        _result = bytes;
        _status = bytes == null
            ? '$label: unreadable image'
            : '$label: ${watch.elapsedMilliseconds} ms, ${bytes.length ~/ 1024} KB';
      });
    } on PlatformException catch (error) {
      setState(() => _status = '$label failed: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('native_photo_kit')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () async {
                  final path = await _sample('landscape.jpg');
                  await _run('formatForFeed', () => NativePhotoKit.formatForFeed(path));
                },
                child: const Text('Format landscape for a 4:5 feed'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final path = await _sample('portrait_exif6.jpg');
                  await _run(
                    'coverJpeg',
                    () => NativePhotoKit.coverJpeg(path, width: 1080, height: 1080),
                  );
                },
                child: const Text('Square crop of an EXIF-rotated portrait'),
              ),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (result != null) Expanded(child: Image.memory(result, fit: BoxFit.contain)),
            ],
          ),
        ),
      ),
    );
  }
}
