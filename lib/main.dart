import 'dart:io';

import 'package:flutter/material.dart';

import 'services/backup/restore_journal.dart';
import 'services/backup/single_instance.dart';
import 'widgets/multi_device_control_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Two instances share SharedPreferences through its cached API and can race
  // the restore journal. Refuse rather than tolerate.
  if (!SingleInstance.claim()) {
    stderr.writeln('Production Control is already running.');
    exit(0);
  }

  // A journal here means a previous restore was interrupted. Roll it back
  // before anything reads configuration, or the app runs on a hybrid of old
  // and new and the next backup uploads that hybrid as a valid revision.
  await RestoreJournal.rollbackIfPresent();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Production Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MultiDeviceControlPage(),
    );
  }
}
