// example/main.dart
// Drop-in showcase of every widget in the Saga brand package.
// Run with `flutter run` from this directory after adding to a Flutter
// project — see the package README for setup.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../lib/saga_brand/saga_brand.dart';

void main() => runApp(const SagaDemoApp());

class SagaDemoApp extends StatelessWidget {
  const SagaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Saga brand demo',
      theme: ThemeData(
        scaffoldBackgroundColor: SagaColors.ink,
        textTheme: GoogleFonts.manropeTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: const SagaDemoScreen(),
    );
  }
}

class SagaDemoScreen extends StatefulWidget {
  const SagaDemoScreen({super.key});

  @override
  State<SagaDemoScreen> createState() => _SagaDemoScreenState();
}

class _SagaDemoScreenState extends State<SagaDemoScreen> {
  SagaMarkState _state = SagaMarkState.playing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // State switcher
              Wrap(
                spacing: 8,
                children: SagaMarkState.values.map((s) {
                  final on = s == _state;
                  return ChoiceChip(
                    label: Text(s.name.toUpperCase()),
                    selected: on,
                    onSelected: (_) => setState(() => _state = s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // Three themes row
              Row(
                children: [
                  for (final t in [SagaTheme.cream, SagaTheme.ink, SagaTheme.terra])
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: t.background,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            AnimatedSagaMark(size: 120, theme: t, state: _state),
                            const SizedBox(height: 16),
                            SagaWordmark(size: 28, theme: t),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 32),
              // Lockup
              Container(
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: SagaColors.cream,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SagaLockup(
                  size: 64,
                  theme: SagaTheme.cream,
                  markState: _state,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
