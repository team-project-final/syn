#!/usr/bin/env bash
# shared-avro.sh — Avro schema scaffold for synapse-shared
# Sourced by phase3.sh. Requires common.sh.

###############################################################################
# shared_init(repo_dir)
#   Create Gradle project with Avro schemas, plugin config, and docs.
###############################################################################
shared_init() {
  local repo_dir="$1"

  log_info "synapse-shared Avro 프로젝트 초기화: $repo_dir"

  # --- settings.gradle.kts ---
  cat > "$repo_dir/settings.gradle.kts" <<'GRADLE'
rootProject.name = "synapse-shared"
GRADLE

  # --- build.gradle.kts ---
  cat > "$repo_dir/build.gradle.kts" <<'GRADLE'
plugins {
    java
    id("com.github.davidmc24.gradle.plugin.avro") version "1.9.1"
    `maven-publish`
}

group = "com.synapse"
version = "0.1.0"

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

repositories {
    mavenCentral()
    maven { url = uri("https://packages.confluent.io/maven/") }
}

dependencies {
    implementation("org.apache.avro:avro:1.11.3")
    implementation("io.confluent:kafka-avro-serializer:7.5.0")
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
        }
    }
}
GRADLE

  # --- Avro schemas ---
  local avro_dir="$repo_dir/src/main/avro"
  mkdir -p "$avro_dir/shared"
  mkdir -p "$avro_dir/platform"

  cat > "$avro_dir/shared/TenantId.avsc" <<'AVRO'
{
  "type": "record",
  "name": "TenantId",
  "namespace": "com.synapse.shared",
  "doc": "Strongly-typed tenant identifier.",
  "fields": [
    {"name": "value", "type": "string", "doc": "UUID string of the tenant"}
  ]
}
AVRO

  cat > "$avro_dir/shared/UserId.avsc" <<'AVRO'
{
  "type": "record",
  "name": "UserId",
  "namespace": "com.synapse.shared",
  "doc": "Strongly-typed user identifier.",
  "fields": [
    {"name": "value", "type": "string", "doc": "UUID string of the user"}
  ]
}
AVRO

  cat > "$avro_dir/shared/CloudEventEnvelope.avsc" <<'AVRO'
{
  "type": "record",
  "name": "CloudEventEnvelope",
  "namespace": "com.synapse.shared",
  "doc": "CloudEvents 1.0 envelope for all Synapse domain events.",
  "fields": [
    {"name": "specversion", "type": "string", "default": "1.0", "doc": "CloudEvents spec version"},
    {"name": "id", "type": "string", "doc": "Unique event identifier (UUID)"},
    {"name": "source", "type": "string", "doc": "Event source URI (e.g. /platform-svc/auth)"},
    {"name": "type", "type": "string", "doc": "Event type (e.g. com.synapse.platform.UserRegistered)"},
    {"name": "subject", "type": ["null", "string"], "default": null, "doc": "Event subject"},
    {"name": "time", "type": "string", "doc": "ISO-8601 timestamp"},
    {"name": "tenantid", "type": "string", "doc": "Tenant identifier"},
    {"name": "datacontenttype", "type": "string", "default": "application/json", "doc": "Content type of data"},
    {"name": "traceparent", "type": ["null", "string"], "default": null, "doc": "W3C Trace Context traceparent header"}
  ]
}
AVRO

  cat > "$avro_dir/platform/UserRegistered.avsc" <<'AVRO'
{
  "type": "record",
  "name": "UserRegistered",
  "namespace": "com.synapse.platform",
  "doc": "Emitted when a new user completes registration.",
  "fields": [
    {"name": "userId", "type": "string", "doc": "UUID of the newly registered user"},
    {"name": "email", "type": "string", "doc": "User email address"},
    {"name": "tenantId", "type": "string", "doc": "Tenant the user belongs to"},
    {"name": "registeredAt", "type": "string", "doc": "ISO-8601 registration timestamp"}
  ]
}
AVRO

  # --- Schema evolution guide ---
  mkdir -p "$repo_dir/docs"
  cat > "$repo_dir/docs/SCHEMA_EVOLUTION.md" <<'MD'
# Schema Evolution Guide

## Backward Compatibility Rules

All Avro schema changes MUST maintain **backward compatibility** — new schema
can read data written by the old schema.

### Allowed Changes

| Change | Safe? | Notes |
|---|---|---|
| Add field with default | Yes | New readers get default for old data |
| Remove field with default | Yes | Old readers ignore missing field |
| Add enum symbol at end | Yes | Existing readers ignore new values |
| Widen numeric type | Yes | e.g. `int` → `long` |

### Forbidden Actions

- **Never** remove a field that has no default value
- **Never** rename a field (add new + deprecate old instead)
- **Never** change a field's type incompatibly (e.g. `string` → `int`)
- **Never** reorder enum symbols
- **Never** change a field's default value semantics

## PR Procedure

1. Create a feature branch from `main`
2. Modify `.avsc` files under `src/main/avro/`
3. Run `./gradlew build` to verify schema compilation
4. Open a PR with:
   - Before/after schema diff
   - Compatibility justification
   - List of affected consumers
5. Require at least **1 approval** from a schema owner
6. CI will run schema compatibility check automatically

## Schema Registry

Schemas are registered in Confluent Schema Registry with
`BACKWARD` compatibility mode. The CI pipeline validates
compatibility before merge.
MD

  log_ok "synapse-shared Avro 프로젝트 생성 완료: $repo_dir"
}
