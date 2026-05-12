#!/usr/bin/env bash
# spring-init.sh — Spring Boot scaffold helpers for polyrepo bootstrap
# Sourced by phase3.sh. Requires common.sh.

###############################################################################
# spring_init(repo_dir, repo_name, artifact, pkg)
#   Download Spring Boot starter from start.spring.io with fallback versions.
#   Adds spring-modulith deps + @Modulithic annotation.
###############################################################################
spring_init() {
  local repo_dir="$1" repo_name="$2" artifact="$3" pkg="$4"

  log_info "Spring Boot 초기화: $repo_name (artifact=$artifact, pkg=$pkg)"

  local versions=("4.0.0" "4.0.0-M3" "3.4.0")
  local downloaded=false

  for ver in "${versions[@]}"; do
    log_info "start.spring.io 시도: Boot $ver"
    local url="https://start.spring.io/starter.zip"
    url+="?type=gradle-project-kotlin"
    url+="&language=java"
    url+="&bootVersion=$ver"
    url+="&groupId=com.synapse"
    url+="&artifactId=$artifact"
    url+="&name=$artifact"
    url+="&packageName=$pkg"
    url+="&javaVersion=21"
    url+="&dependencies=web,actuator,validation"

    local zip_file="$BOOTSTRAP_TMP/${artifact}.zip"
    if curl -fsSL "$url" -o "$zip_file" 2>/dev/null; then
      log_ok "start.spring.io 다운로드 성공: Boot $ver"
      downloaded=true
      break
    else
      log_warn "Boot $ver 실패 — 다음 버전 시도"
    fi
  done

  if [ "$downloaded" != "true" ]; then
    log_error "start.spring.io 다운로드 전부 실패: $repo_name"
    return 1
  fi

  # Unzip to repo_dir
  unzip -qo "$zip_file" -d "$repo_dir"
  rm -f "$zip_file"
  log_ok "프로젝트 압축 해제 완료: $repo_dir"

  # --- Add spring-modulith dependencies ---
  local build_file="$repo_dir/build.gradle.kts"
  if [ -f "$build_file" ]; then
    # Add modulith BOM + starter deps before the closing brace of dependencies block
    # Insert after the last dependency line
    local modulith_deps
    modulith_deps=$(cat <<'DEPS'

    // Spring Modulith
    implementation("org.springframework.modulith:spring-modulith-starter-core")
    testImplementation("org.springframework.modulith:spring-modulith-starter-test")
DEPS
    )

    # Find dependencies block and append modulith deps
    if grep -q "^dependencies" "$build_file"; then
      sed -i '/^dependencies/,/^}/ {
        /^}/ i\
\    // Spring Modulith\
\    implementation("org.springframework.modulith:spring-modulith-starter-core")\
\    testImplementation("org.springframework.modulith:spring-modulith-starter-test")
      }' "$build_file"
    else
      # Fallback: append dependencies block
      cat >> "$build_file" <<'BUILD'

dependencies {
    implementation("org.springframework.modulith:spring-modulith-starter-core")
    testImplementation("org.springframework.modulith:spring-modulith-starter-test")
}
BUILD
    fi

    # Add modulith BOM in dependencyManagement
    if ! grep -q "spring-modulith-bom" "$build_file"; then
      cat >> "$build_file" <<'BOM'

dependencyManagement {
    imports {
        mavenBom("org.springframework.modulith:spring-modulith-bom:1.3.0")
    }
}
BOM
    fi

    log_ok "spring-modulith 의존성 추가 완료"
  fi

  # --- Add @Modulithic annotation to Application class ---
  local pkg_path="${pkg//./\/}"
  local app_class
  app_class=$(find "$repo_dir/src/main/java/$pkg_path" -name "*Application.java" 2>/dev/null | head -1)

  if [ -n "$app_class" ] && [ -f "$app_class" ]; then
    # Add import
    sed -i '/^import org.springframework.boot.autoconfigure.SpringBootApplication;/a import org.springframework.modulith.Modulithic;' "$app_class"
    # Add annotation before @SpringBootApplication
    sed -i 's/@SpringBootApplication/@Modulithic\n@SpringBootApplication/' "$app_class"
    log_ok "@Modulithic 어노테이션 추가 완료: $app_class"
  else
    log_warn "Application 클래스를 찾을 수 없음: $repo_name"
  fi
}

###############################################################################
# spring_create_modules(repo_dir, pkg, modules...)
#   Create Spring Modulith module directories with package-info + placeholder.
#   Also creates a shared module.
###############################################################################
spring_create_modules() {
  local repo_dir="$1" pkg="$2"
  shift 2
  local modules=("$@")

  local pkg_path="${pkg//./\/}"
  local base_dir="$repo_dir/src/main/java/$pkg_path"

  # Create shared module first
  local shared_dir="$base_dir/shared"
  mkdir -p "$shared_dir"

  cat > "$shared_dir/package-info.java" <<JAVA
@org.springframework.modulith.ApplicationModule(
    displayName = "Shared",
    allowedDependencies = {}
)
package ${pkg}.shared;
JAVA

  cat > "$shared_dir/PlaceholderComponent.java" <<JAVA
package ${pkg}.shared;

import org.springframework.stereotype.Component;

@Component
public class PlaceholderComponent {
    // Bootstrap placeholder — replace with real shared utilities
}
JAVA

  log_ok "shared 모듈 생성 완료"

  # Create each module
  for mod in "${modules[@]}"; do
    local mod_dir="$base_dir/$mod"
    mkdir -p "$mod_dir"

    cat > "$mod_dir/package-info.java" <<JAVA
@org.springframework.modulith.ApplicationModule(
    displayName = "${mod^}",
    allowedDependencies = {"shared"}
)
package ${pkg}.${mod};
JAVA

    cat > "$mod_dir/PlaceholderComponent.java" <<JAVA
package ${pkg}.${mod};

import org.springframework.stereotype.Component;

@Component
public class PlaceholderComponent {
    // Bootstrap placeholder — replace with real ${mod} implementation
}
JAVA

    log_ok "모듈 생성 완료: $mod"
  done
}

###############################################################################
# spring_create_modulith_test(repo_dir, pkg, artifact)
#   Create ModuleStructureTest that verifies modulith structure.
###############################################################################
spring_create_modulith_test() {
  local repo_dir="$1" pkg="$2" artifact="$3"

  local pkg_path="${pkg//./\/}"
  local test_dir="$repo_dir/src/test/java/$pkg_path"
  mkdir -p "$test_dir"

  cat > "$test_dir/ModuleStructureTest.java" <<JAVA
package ${pkg};

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

class ModuleStructureTest {

    @Test
    void verifyModuleStructure() {
        ApplicationModules.of(${artifact^}Application.class).verify();
    }
}
JAVA

  # Capitalize first letter of artifact for class name
  local class_name
  class_name=$(echo "$artifact" | sed 's/\b\(.\)/\u\1/g; s/-//g')
  # Fix: use proper class name pattern based on actual generated Application class
  local app_class_name
  app_class_name=$(find "$repo_dir/src/main/java/$pkg_path" -name "*Application.java" 2>/dev/null | head -1 | xargs -r basename | sed 's/\.java$//')

  if [ -n "$app_class_name" ]; then
    sed -i "s/${artifact^}Application.class/${app_class_name}.class/" "$test_dir/ModuleStructureTest.java"
  fi

  log_ok "ModuleStructureTest 생성 완료: $repo_dir"
}
