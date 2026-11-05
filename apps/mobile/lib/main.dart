import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/export_file.dart';
import 'core/local_database.dart';
import 'core/repository.dart';
import 'core/strings.dart';
import 'design_system/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<Repository> loading;
  String language = 'uz';
  @override
  void initState() {
    super.initState();
    loading = initialize();
  }

  Future<Repository> initialize() async {
    const url = String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://10.0.2.2:8080',
    );
    if (kReleaseMode && !url.startsWith('https://')) {
      throw StateError('Release requires an HTTPS API_URL');
    }
    LocalDatabase? db;
    try {
      db = await LocalDatabase.open();
      final repo = Repository(
        db,
        const FlutterSecureStorage(),
        Dio(
          BaseOptions(
            baseUrl: url,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 15),
          ),
        ),
      );
      await repo.restore();
      return repo;
    } catch (_) {
      if (db != null) await db.close();
      rethrow;
    }
  }

  Future<void> exportLocal(BuildContext context) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final files = <String, String>{};
      for (final name in [
        'savdo.sqlite',
        'savdo.sqlite-wal',
        'savdo.sqlite-shm',
      ]) {
        final f = File('${directory.path}/$name');
        if (await f.exists()) files[name] = base64Encode(await f.readAsBytes());
      }
      await ExportFile.saveJson({
        'format': 'savdoyordam-local-recovery-v1',
        'encoding': 'base64',
        'files': files,
      }, 'SavdoYordam-local-recovery.json');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.text['exportError'])));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Repository>(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(snapshot.data!)],
          child: const SavdoApp(),
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        locale: Locale(language),
        supportedLocales: const [Locale('uz'), Locale('ru')],
        localizationsDelegates: const [
          Strings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: snapshot.hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.folder_off_outlined,
                              size: 48,
                              color: muted,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              context.text['startupError'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(context.text['startupErrorHint']),
                            const SizedBox(height: 24),
                            AppButton(
                              label: context.text['retry'],
                              onPressed: () =>
                                  setState(() => loading = initialize()),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => exportLocal(context),
                              icon: const Icon(Icons.save_alt),
                              label: Text(context.text['saveLocalCopy']),
                            ),
                            const SizedBox(height: 24),
                            TextButton(
                              onPressed: () => setState(
                                () => language = language == 'uz' ? 'ru' : 'uz',
                              ),
                              child: Text(
                                language == 'uz' ? 'Русский' : 'O‘zbekcha',
                              ),
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
