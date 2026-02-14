#!/bin/bash
# Script 1: Configuration and Parameters
# This script defines all the parameters and configuration needed for the Windows ISO download process

set -euo pipefail

# Function to display usage
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --windows-target-name STRING    Target Windows version (required)
  --destination-directory STRING  Output directory (default: output)
  --architecture STRING          Architecture: x64 or arm64 (default: x64)
  --edition STRING               Edition: pro, core, multi, or home (default: pro)
  --lang STRING                  Language code (default: en-us)
  --esd                          Enable ESD flag
  --drivers                      Enable drivers flag
  --netfx3                       Enable .NET Framework 3 flag
  -h, --help                     Display this help message

Valid architectures: x64, arm64
Valid editions: pro, core, multi, home
Valid languages: nb-no, fr-ca, fi-fi, lv-lv, es-es, en-gb, zh-tw, th-th, sv-se, 
  en-us, es-mx, bg-bg, hr-hr, pt-br, el-gr, cs-cz, it-it, sk-sk, pl-pl, sl-si, 
  neutral, ja-jp, et-ee, ro-ro, fr-fr, pt-pt, ar-sa, lt-lt, hu-hu, da-dk, zh-cn, 
  uk-ua, tr-tr, ru-ru, nl-nl, he-il, ko-kr, sr-latn-rs, de-de

EOF
  exit 1
}

# Default values
windows_target_name=""
destination_directory="output"
architecture="x64"
edition="pro"
lang="en-us"
esd=false
drivers=false
netfx3=false

# Valid options arrays
valid_architectures=("x64" "arm64")
valid_editions=("pro" "core" "multi" "home")
valid_langs=("nb-no" "fr-ca" "fi-fi" "lv-lv" "es-es" "en-gb" "zh-tw" "th-th" "sv-se" "en-us" "es-mx" "bg-bg" "hr-hr" "pt-br" "el-gr" "cs-cz" "it-it" "sk-sk" "pl-pl" "sl-si" "neutral" "ja-jp" "et-ee" "ro-ro" "fr-fr" "pt-pt" "ar-sa" "lt-lt" "hu-hu" "da-dk" "zh-cn" "uk-ua" "tr-tr" "ru-ru" "nl-nl" "he-il" "ko-kr" "sr-latn-rs" "de-de")

# Function to check if value is in array
contains() {
  local value="$1"
  shift
  local array=("$@")
  for item in "${array[@]}"; do
    if [[ "$item" == "$value" ]]; then
      return 0
    fi
  done
  return 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --windows-target-name)
      windows_target_name="$2"
      shift 2
      ;;
    --destination-directory)
      destination_directory="$2"
      shift 2
      ;;
    --architecture)
      architecture="$2"
      shift 2
      ;;
    --edition)
      edition="$2"
      shift 2
      ;;
    --lang)
      lang="$2"
      shift 2
      ;;
    --esd)
      esd=true
      shift
      ;;
    --drivers)
      drivers=true
      shift
      ;;
    --netfx3)
      netfx3=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      usage
      ;;
  esac
done

# Error handling function
error_exit() {
  echo "ERROR: $1" >&2
  exit 1
}

# Validation
if [[ -z "$windows_target_name" ]]; then
  error_exit "windows-target-name is required"
fi

if ! contains "$architecture" "${valid_architectures[@]}"; then
  error_exit "Invalid architecture: $architecture. Must be one of: ${valid_architectures[*]}"
fi

if ! contains "$edition" "${valid_editions[@]}"; then
  error_exit "Invalid edition: $edition. Must be one of: ${valid_editions[*]}"
fi

if ! contains "$lang" "${valid_langs[@]}"; then
  error_exit "Invalid language: $lang"
fi

# Set global variables
preview=false
ring_lower=""

# Determine architecture
if [[ "$architecture" == "x64" ]]; then
  arch="amd64"
else
  arch="arm64"
fi

# Check if this is a preview build
if [[ "$windows_target_name" =~ (beta|dev|wif|canary) ]]; then
  preview=true
  # Extract the matched ring type
  if [[ "$windows_target_name" =~ beta ]]; then
    ring_lower="beta"
  elif [[ "$windows_target_name" =~ dev ]]; then
    ring_lower="dev"
  elif [[ "$windows_target_name" =~ wif ]]; then
    ring_lower="wif"
  elif [[ "$windows_target_name" =~ canary ]]; then
    ring_lower="canary"
  fi
fi

# Function to get edition name
get_edition_name() {
  local e="$1"
  case "${e,,}" in
    core|home)
      echo "Core"
      ;;
    multi)
      echo "Multi"
      ;;
    *)
      echo "Professional"
      ;;
  esac
}

edition_name=$(get_edition_name "$edition")

# Define Windows targets (using associative arrays)
declare -A TARGET_windows_10=(
  [search]="windows 10 19045 $arch"
  [edition]="$edition_name"
)

declare -A TARGET_windows_11old=(
  [search]="windows 11 22631 $arch"
  [edition]="$edition_name"
)

declare -A TARGET_windows_11=(
  [search]="windows 11 26100 $arch"
  [edition]="$edition_name"
)

declare -A TARGET_windows_11new=(
  [search]="windows 11 26200 $arch"
  [edition]="$edition_name"
)

declare -A TARGET_windows_11beta=(
  [search]="windows 11 26120 $arch"
  [edition]="$edition_name"
  [ring]="Beta"
)

declare -A TARGET_windows_11dev=(
  [search]="windows 11 26220 $arch"
  [edition]="$edition_name"
  [ring]="Wif"
)

declare -A TARGET_windows_11canary=(
  [search]="windows 11 $arch"
  [edition]="$edition_name"
  [ring]="Canary"
)

# Export configuration as a JSON file for other scripts to use
config_path="./windows-iso-config.json"

# Convert bash booleans to lowercase strings for jq
esd_json=$(if $esd; then echo "true"; else echo "false"; fi)
drivers_json=$(if $drivers; then echo "true"; else echo "false"; fi)
netfx3_json=$(if $netfx3; then echo "true"; else echo "false"; fi)
preview_json=$(if $preview; then echo "true"; else echo "false"; fi)

# Build JSON manually (or use jq if available)
if command -v jq &> /dev/null; then
  # Use jq to create proper JSON
  jq -n \
    --arg windowsTargetName "$windows_target_name" \
    --arg destinationDirectory "$destination_directory" \
    --arg architecture "$architecture" \
    --arg arch "$arch" \
    --arg edition "$edition" \
    --arg lang "$lang" \
    --argjson esd "$esd_json" \
    --argjson drivers "$drivers_json" \
    --argjson netfx3 "$netfx3_json" \
    --argjson preview "$preview_json" \
    --arg ringLower "$ring_lower" \
    '{
      windowsTargetName: $windowsTargetName,
      destinationDirectory: $destinationDirectory,
      architecture: $architecture,
      arch: $arch,
      edition: $edition,
      lang: $lang,
      esd: $esd,
      drivers: $drivers,
      netfx3: $netfx3,
      preview: $preview,
      ringLower: $ringLower,
      targets: {
        "windows-10": {
          search: "windows 10 19045 \($arch)",
          edition: "'"$edition_name"'"
        },
        "windows-11old": {
          search: "windows 11 22631 \($arch)",
          edition: "'"$edition_name"'"
        },
        "windows-11": {
          search: "windows 11 26100 \($arch)",
          edition: "'"$edition_name"'"
        },
        "windows-11new": {
          search: "windows 11 26200 \($arch)",
          edition: "'"$edition_name"'"
        },
        "windows-11beta": {
          search: "windows 11 26120 \($arch)",
          edition: "'"$edition_name"'",
          ring: "Beta"
        },
        "windows-11dev": {
          search: "windows 11 26220 \($arch)",
          edition: "'"$edition_name"'",
          ring: "Wif"
        },
        "windows-11canary": {
          search: "windows 11 \($arch)",
          edition: "'"$edition_name"'",
          ring: "Canary"
        }
      }
    }' > "$config_path"
else
  # Fallback: create JSON manually without jq
  cat > "$config_path" << EOF
{
  "windowsTargetName": "$windows_target_name",
  "destinationDirectory": "$destination_directory",
  "architecture": "$architecture",
  "arch": "$arch",
  "edition": "$edition",
  "lang": "$lang",
  "esd": $esd_json,
  "drivers": $drivers_json,
  "netfx3": $netfx3_json,
  "preview": $preview_json,
  "ringLower": "$ring_lower",
  "targets": {
    "windows-10": {
      "search": "windows 10 19045 $arch",
      "edition": "$edition_name"
    },
    "windows-11old": {
      "search": "windows 11 22631 $arch",
      "edition": "$edition_name"
    },
    "windows-11": {
      "search": "windows 11 26100 $arch",
      "edition": "$edition_name"
    },
    "windows-11new": {
      "search": "windows 11 26200 $arch",
      "edition": "$edition_name"
    },
    "windows-11beta": {
      "search": "windows 11 26120 $arch",
      "edition": "$edition_name",
      "ring": "Beta"
    },
    "windows-11dev": {
      "search": "windows 11 26220 $arch",
      "edition": "$edition_name",
      "ring": "Wif"
    },
    "windows-11canary": {
      "search": "windows 11 $arch",
      "edition": "$edition_name",
      "ring": "Canary"
    }
  }
}
EOF
fi

echo "Configuration saved to $config_path"
echo "Target: $windows_target_name"
echo "Architecture: $architecture ($arch)"
echo "Edition: $edition"
echo "Language: $lang"
echo "Preview: $preview"