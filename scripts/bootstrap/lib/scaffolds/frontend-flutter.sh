#!/usr/bin/env bash
# frontend-flutter.sh — Flutter scaffold for synapse-frontend
# Sourced by phase3.sh. Requires common.sh.

###############################################################################
# frontend_init(repo_dir)
#   Create Flutter project with feature-first architecture + design system.
###############################################################################
frontend_init() {
  local repo_dir="$1"

  log_info "Flutter 프로젝트 초기화: $repo_dir"

  # --- flutter create ---
  flutter create \
    --org com.synapse \
    --platforms web,android,ios \
    --overwrite \
    "$repo_dir"

  # --- Custom pubspec.yaml ---
  cat > "$repo_dir/pubspec.yaml" <<'YAML'
name: synapse_frontend
description: Synapse — Flutter frontend (web/mobile)
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: '>=3.5.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.0.0
  go_router: ^14.0.0
  dio: ^5.4.0
  google_fonts: ^6.2.0
  hive_flutter: ^1.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  build_runner: ^2.4.0
  riverpod_generator: ^2.4.0
  mockito: ^5.4.0
YAML

  # --- Feature-first lib structure ---
  local lib="$repo_dir/lib"
  mkdir -p "$lib/core/constants"
  mkdir -p "$lib/core/theme"
  mkdir -p "$lib/core/network"
  mkdir -p "$lib/core/error"
  mkdir -p "$lib/core/utils"
  mkdir -p "$lib/shared/widgets"
  mkdir -p "$lib/shared/models"
  mkdir -p "$lib/features/dashboard/presentation"

  # --- main.dart ---
  cat > "$lib/main.dart" <<'DART'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: SynapseApp(),
    ),
  );
}
DART

  # --- app.dart ---
  cat > "$lib/app.dart" <<'DART'
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_routes.dart';

class SynapseApp extends StatelessWidget {
  const SynapseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Synapse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(AppColors.primaryAmber),
        fontFamily: 'Pretendard',
      ),
      routerConfig: appRouter,
    );
  }
}
DART

  # --- app_colors.dart ---
  cat > "$lib/core/theme/app_colors.dart" <<'DART'
/// Design-system color tokens for Synapse.
abstract final class AppColors {
  // ── Primary ──
  static const int primaryAmber = 0xFFD97706;
  static const int primaryHover = 0xFFB45309;

  // ── Stone scale ──
  static const int stone50 = 0xFFFAFAF9;
  static const int stone100 = 0xFFF5F5F4;
  static const int stone200 = 0xFFE7E5E4;
  static const int stone300 = 0xFFD6D3D1;
  static const int stone400 = 0xFFA8A29E;
  static const int stone500 = 0xFF78716C;
  static const int stone600 = 0xFF57534E;
  static const int stone700 = 0xFF44403C;
  static const int stone800 = 0xFF292524;
  static const int stone900 = 0xFF1C1917;

  // ── Semantic ──
  static const int success = 0xFF16A34A;
  static const int warning = 0xFFEAB308;
  static const int error = 0xFFDC2626;
  static const int info = 0xFF2563EB;
}
DART

  # --- app_spacing.dart ---
  cat > "$lib/core/theme/app_spacing.dart" <<'DART'
/// Design-system spacing tokens for Synapse.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}
DART

  # --- app_routes.dart ---
  cat > "$lib/core/theme/app_routes.dart" <<'DART'
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardScreen(),
    ),
  ],
);
DART

  # --- dashboard_screen.dart ---
  cat > "$lib/features/dashboard/presentation/dashboard_screen.dart" <<'DART'
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synapse'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Synapse',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Your learning companion',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
DART

  # --- analysis_options.yaml ---
  cat > "$repo_dir/analysis_options.yaml" <<'YAML'
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    # Style
    prefer_single_quotes: true
    always_use_package_imports: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_declarations: true
    prefer_final_locals: true
    sort_constructors_first: true
    unawaited_futures: true

    # Safety
    avoid_dynamic_calls: true
    cancel_subscriptions: true
    close_sinks: true
    literal_only_boolean_expressions: true

    # Documentation
    public_member_api_docs: false

analyzer:
  errors:
    missing_return: error
    dead_code: warning
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
YAML

  log_ok "Flutter 프로젝트 생성 완료: $repo_dir"
}
