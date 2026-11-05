import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../design_system/theme.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false, showPassword = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final s = context.text;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'uz', label: Text('O‘zbekcha')),
                          ButtonSegment(value: 'ru', label: Text('Русский')),
                        ],
                        selected: {repo.language},
                        onSelectionChanged: (v) => repo.setLanguage(v.first),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: brand,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.storefront_outlined,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      s['appName'],
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s['tagline'],
                      style: const TextStyle(
                        color: brand,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      s[register ? 'register' : 'login'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s['welcomeBody'],
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: email,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: s['email'],
                        prefixIcon: const Icon(Icons.mail_outline),
                      ),
                      validator: (v) =>
                          (v ?? '').contains('@') ? null : s['validRequired'],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      autofillHints: [
                        register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      obscureText: !showPassword,
                      decoration: InputDecoration(
                        labelText: s['password'],
                        suffixIcon: IconButton(
                          tooltip:
                              s[showPassword ? 'hidePassword' : 'showPassword'],
                          onPressed: () =>
                              setState(() => showPassword = !showPassword),
                          icon: Icon(
                            showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').length >= 12 ? null : s['validRequired'],
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: s[register ? 'register' : 'login'],
                      busy: busy,
                      onPressed: () async {
                        if (!form.currentState!.validate()) return;
                        setState(() => busy = true);
                        try {
                          await repo.authenticate(
                            email.text.trim(),
                            password.text,
                            register,
                          );
                          refreshData(ref);
                          if (context.mounted) {
                            context.go(repo.hasStore ? '/home' : '/onboarding');
                          }
                        } on OperationFailure catch (e) {
                          if (context.mounted) message(context, e.code);
                        } catch (_) {
                          if (context.mounted) message(context, 'server_error');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => register = !register),
                      child: Text(s[register ? 'login' : 'register']),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  final name = TextEditingController();
  String retailType = 'general';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.text['appName'])),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.storefront_outlined, size: 64, color: brand),
          const SizedBox(height: 24),
          Text(
            context.text['storeIntro'],
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: context.text['storeName']),
            maxLength: 100,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: retailType,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.text['retailType']),
            items: [
              for (final v in [
                'general',
                'grocery',
                'clothing',
                'household',
                'other',
              ])
                DropdownMenuItem(value: v, child: Text(context.text[v])),
            ],
            onChanged: (v) => setState(() => retailType = v ?? 'general'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.key_outlined),
            label: Text(context.text['joinStore']),
            onPressed: () async {
              final value = await appForm(context, 'joinStore', [
                const FieldSpec('token', 'invitationCode'),
              ]);
              if (value == null || !context.mounted) return;
              await perform(
                context,
                ref,
                () => ref
                    .read(repositoryProvider)
                    .acceptInvitation(value['token']!),
              );
              if (context.mounted && ref.read(repositoryProvider).hasStore) {
                context.go('/home');
              }
            },
          ),
          const SizedBox(height: 16),
          AppButton(
            label: context.text['createStore'],
            busy: busy,
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                message(context, 'validRequired');
                return;
              }
              setState(() => busy = true);
              try {
                await ref
                    .read(repositoryProvider)
                    .createStore(name.text.trim(), retailType: retailType);
                if (context.mounted) context.go('/products');
              } on OperationFailure catch (e) {
                if (context.mounted) message(context, e.code);
              } catch (_) {
                if (context.mounted) message(context, 'server_error');
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
          ),
        ],
      ),
    ),
  );
}
