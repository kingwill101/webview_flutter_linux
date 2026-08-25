// SPDX-License-Identifier: UNLICENSED

import 'dart:io';

const cefRepository = 'https://github.com/tauri-apps/cef-rs.git';
const cefRevision = 'a2e15ae659c4b3957883e34de879bd8b38360ce5';

Future<void> main(List<String> arguments) async {
  final project = Directory.current.absolute;
  if (!File.fromUri(project.uri.resolve('pubspec.yaml')).existsSync()) {
    stderr.writeln('Run this command from the Flutter project root.');
    exitCode = 64;
    return;
  }

  final cefDirectory = Directory.fromUri(
    project.uri.resolve('third_party/cef/'),
  );
  final force = arguments.contains('--force');
  if (File.fromUri(cefDirectory.uri.resolve('archive.json')).existsSync() &&
      !force) {
    stdout.writeln('CEF is already installed at ${cefDirectory.path}.');
    return;
  }

  final sourceDirectory = Directory.fromUri(
    project.uri.resolve('.dart_tool/cef-rs-source/'),
  );
  final targetDirectory = Directory.fromUri(
    project.uri.resolve('.dart_tool/cef-rs-target/'),
  );
  sourceDirectory.createSync(recursive: true);
  targetDirectory.createSync(recursive: true);

  if (!Directory.fromUri(sourceDirectory.uri.resolve('.git/')).existsSync()) {
    await _run('git', ['init'], workingDirectory: sourceDirectory.path);
    await _run('git', [
      'remote',
      'add',
      'origin',
      cefRepository,
    ], workingDirectory: sourceDirectory.path);
  }
  await _run('git', [
    'fetch',
    '--depth',
    '1',
    'origin',
    cefRevision,
  ], workingDirectory: sourceDirectory.path);
  await _run('git', [
    'checkout',
    '--detach',
    'FETCH_HEAD',
  ], workingDirectory: sourceDirectory.path);

  await _run('rustup', [
    'run',
    '1.95.0',
    'cargo',
    'run',
    '--manifest-path',
    File.fromUri(sourceDirectory.uri.resolve('Cargo.toml')).path,
    '--target-dir',
    targetDirectory.path,
    '-p',
    'export-cef-dir',
    '--',
    '--force',
    cefDirectory.path,
  ]);
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  stdout.writeln('\$ $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final status = await process.exitCode;
  if (status != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Process exited with status $status.',
      status,
    );
  }
}
