#!/usr/bin/env bash

# Populate detected_tools and detected_versions for the current directory.
# The caller must source languages.defaults before invoking this function.
detect_project_stack() {
  detected_tools=()
  detected_versions=()

  if [ -f package.json ]; then
    local node_ver=""
    if command -v jq >/dev/null 2>&1; then
      local raw
      raw=$(jq -r '.engines.node // empty' package.json 2>/dev/null || true)
      if [ -n "$raw" ] && [ "$raw" != "null" ]; then
        local cleaned
        cleaned=$(printf '%s' "$raw" | tr -d '"' | sed -E 's/[\^~><= ]//g')
        node_ver=$(printf '%s' "$cleaned" | grep -Eo '^[0-9]+(\.[0-9]+)?' | head -n1)
      fi
    fi
    detected_tools+=("node")
    detected_versions+=("${node_ver:-${node:-22}}")
  fi

  if [ -f go.mod ]; then
    local go_ver
    go_ver=$(awk '/^go[[:space:]]/{print $2; exit}' go.mod 2>/dev/null)
    detected_tools+=("go")
    detected_versions+=("${go_ver:-${go:-1.23}}")
  fi

  if [ -f Cargo.toml ]; then
    local rust_ver=""
    if grep -qE '^[[:space:]]*rust-version' Cargo.toml 2>/dev/null; then
      rust_ver=$(awk -F'"' '/^[[:space:]]*rust-version/ {print $2; exit}' Cargo.toml 2>/dev/null)
    fi
    detected_tools+=("rust")
    detected_versions+=("${rust_ver:-${rust:-stable}}")
  fi

  if [ -f composer.json ]; then
    local php_ver=""
    if command -v jq >/dev/null 2>&1; then
      local raw
      raw=$(jq -r '.require.php // empty' composer.json 2>/dev/null || true)
      if [ -n "$raw" ] && [ "$raw" != "null" ]; then
        php_ver=$(printf '%s' "$raw" | tr -d '"' | sed -E 's/[\^~><= ]//g' | grep -Eo '^[0-9]+(\.[0-9]+)?' | head -n1)
      fi
    fi
    detected_tools+=("php")
    detected_versions+=("${php_ver:-${php:-8.3}}")
  fi

  if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
    local python_ver=""
    if [ -f pyproject.toml ]; then
      local raw
      raw=$(awk -F'"' '/requires-python/ {print $2; exit}' pyproject.toml 2>/dev/null)
      if [ -n "$raw" ]; then
        python_ver=$(printf '%s' "$raw" | sed -E 's/[<>=~^ ]//g' | grep -Eo '^[0-9]+(\.[0-9]+)?' | head -n1)
      fi
    fi
    detected_tools+=("python")
    detected_versions+=("${python_ver:-${python:-3.12}}")
  fi
}
