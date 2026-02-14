#!/bin/bash
# Test script for config-and-parameters.sh
# This script tests various scenarios and validates the JSON output

set -euo pipefail

# Get the directory where this test script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default script path (next to this test script)
DEFAULT_SCRIPT_PATH="$SCRIPT_DIR/config-and-parameters.sh"

# Allow override via command line argument
SCRIPT_PATH="${1:-$DEFAULT_SCRIPT_PATH}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
  cat << EOF
Usage: $0 [SCRIPT_PATH]

Arguments:
  SCRIPT_PATH    Path to config-and-parameters.sh to test
                 (default: config-and-parameters.sh in same directory as this test script)

Examples:
  $0                                    # Test script in same directory
  $0 ./config-and-parameters.sh         # Test script in current directory
  $0 /path/to/config-and-parameters.sh  # Test script at specific path

EOF
  exit 1
}

# Check for help flag
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print test results
print_result() {
  local test_name="$1"
  local result="$2"
  local message="${3:-}"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$result" == "PASS" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗ FAIL${NC}: $test_name"
    if [[ -n "$message" ]]; then
      echo -e "  ${RED}Error: $message${NC}"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Function to validate JSON structure
validate_json() {
  local json_file="$1"
  local expected_key="$2"
  local expected_value="$3"
  
  if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not installed, skipping detailed JSON validation${NC}"
    return 0
  fi
  
  local actual_value
  actual_value=$(jq -r ".$expected_key" "$json_file" 2>/dev/null || echo "")
  
  if [[ "$actual_value" == "$expected_value" ]]; then
    return 0
  else
    echo "Expected: $expected_value, Got: $actual_value"
    return 1
  fi
}

# Function to run a test case
run_test() {
  local test_name="$1"
  shift
  local args=("$@")
  
  echo ""
  echo "Running: $test_name"
  
  # Clean up previous test output
  rm -f ./windows-iso-config.json
  
  # Run the script
  if "$SCRIPT_PATH" "${args[@]}" > /dev/null 2>&1; then
    if [[ -f ./windows-iso-config.json ]]; then
      print_result "$test_name" "PASS"
      return 0
    else
      print_result "$test_name" "FAIL" "JSON file not created"
      return 1
    fi
  else
    print_result "$test_name" "FAIL" "Script execution failed"
    return 1
  fi
}

# Function to run a test that should fail
run_negative_test() {
  local test_name="$1"
  shift
  local args=("$@")
  
  echo ""
  echo "Running: $test_name (should fail)"
  
  # Clean up previous test output
  rm -f ./windows-iso-config.json
  
  # Run the script - it should fail
  if "$SCRIPT_PATH" "${args[@]}" > /dev/null 2>&1; then
    print_result "$test_name" "FAIL" "Script should have failed but succeeded"
    return 1
  else
    print_result "$test_name" "PASS"
    return 0
  fi
}

# Function to validate specific JSON fields
validate_json_output() {
  local test_name="$1"
  local json_file="./windows-iso-config.json"
  
  if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Skipping JSON validation (jq not installed)${NC}"
    return 0
  fi
  
  shift
  local validations=("$@")
  
  local all_valid=true
  for validation in "${validations[@]}"; do
    IFS='=' read -r key value <<< "$validation"
    if ! validate_json "$json_file" "$key" "$value"; then
      all_valid=false
      echo "  Failed validation: $key should be $value"
    fi
  done
  
  if $all_valid; then
    print_result "$test_name - JSON validation" "PASS"
  else
    print_result "$test_name - JSON validation" "FAIL"
  fi
}

echo "========================================="
echo "Testing Configuration Script"
echo "========================================="
echo "Script path: $SCRIPT_PATH"
echo ""

# Check if script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo -e "${RED}ERROR: Script not found at: $SCRIPT_PATH${NC}"
  echo ""
  echo "Please ensure the script exists or provide the correct path:"
  echo "  $0 /path/to/config-and-parameters.sh"
  exit 1
fi

# Make sure script is executable
chmod +x "$SCRIPT_PATH"

echo ""
echo "=== Positive Tests ==="

# Test 1: Basic execution with minimal parameters
run_test "Test 1: Basic execution with Windows 11" \
  --windows-target-name "windows-11"

validate_json_output "Test 1" \
  "windowsTargetName=windows-11" \
  "architecture=x64" \
  "edition=pro" \
  "lang=en-us" \
  "preview=false"

# Test 2: Windows 10 with custom directory
run_test "Test 2: Windows 10 with custom directory" \
  --windows-target-name "windows-10" \
  --destination-directory "my-output"

validate_json_output "Test 2" \
  "windowsTargetName=windows-10" \
  "destinationDirectory=my-output"

# Test 3: ARM64 architecture
run_test "Test 3: ARM64 architecture" \
  --windows-target-name "windows-11" \
  --architecture "arm64"

validate_json_output "Test 3" \
  "architecture=arm64" \
  "arch=arm64"

# Test 4: Different editions
run_test "Test 4a: Core edition" \
  --windows-target-name "windows-11" \
  --edition "core"

validate_json_output "Test 4a" \
  "edition=core"

run_test "Test 4b: Home edition" \
  --windows-target-name "windows-11" \
  --edition "home"

validate_json_output "Test 4b" \
  "edition=home"

run_test "Test 4c: Multi edition" \
  --windows-target-name "windows-11" \
  --edition "multi"

validate_json_output "Test 4c" \
  "edition=multi"

# Test 5: Different languages
run_test "Test 5a: French language" \
  --windows-target-name "windows-11" \
  --lang "fr-fr"

validate_json_output "Test 5a" \
  "lang=fr-fr"

run_test "Test 5b: German language" \
  --windows-target-name "windows-11" \
  --lang "de-de"

validate_json_output "Test 5b" \
  "lang=de-de"

run_test "Test 5c: Japanese language" \
  --windows-target-name "windows-11" \
  --lang "ja-jp"

validate_json_output "Test 5c" \
  "lang=ja-jp"

# Test 6: Boolean flags
run_test "Test 6: All boolean flags enabled" \
  --windows-target-name "windows-11" \
  --esd \
  --drivers \
  --netfx3

validate_json_output "Test 6" \
  "esd=true" \
  "drivers=true" \
  "netfx3=true"

# Test 7: Preview builds
run_test "Test 7a: Beta build" \
  --windows-target-name "windows-11beta"

validate_json_output "Test 7a" \
  "preview=true" \
  "ringLower=beta"

run_test "Test 7b: Dev build" \
  --windows-target-name "windows-11dev"

validate_json_output "Test 7b" \
  "preview=true" \
  "ringLower=dev"

run_test "Test 7c: Canary build" \
  --windows-target-name "windows-11canary"

validate_json_output "Test 7c" \
  "preview=true" \
  "ringLower=canary"

# Test 8: Complex combination
run_test "Test 8: Complex combination" \
  --windows-target-name "windows-11" \
  --destination-directory "iso-output" \
  --architecture "arm64" \
  --edition "multi" \
  --lang "es-es" \
  --esd \
  --drivers

validate_json_output "Test 8" \
  "windowsTargetName=windows-11" \
  "destinationDirectory=iso-output" \
  "architecture=arm64" \
  "edition=multi" \
  "lang=es-es" \
  "esd=true" \
  "drivers=true" \
  "netfx3=false"

echo ""
echo "=== Negative Tests (should fail) ==="

# Test 9: Missing required parameter
run_negative_test "Test 9: Missing windows-target-name"

# Test 10: Invalid architecture
run_negative_test "Test 10: Invalid architecture" \
  --windows-target-name "windows-11" \
  --architecture "x86"

# Test 11: Invalid edition
run_negative_test "Test 11: Invalid edition" \
  --windows-target-name "windows-11" \
  --edition "ultimate"

# Test 12: Invalid language
run_negative_test "Test 12: Invalid language" \
  --windows-target-name "windows-11" \
  --lang "xx-xx"

# Test 13: Invalid option
run_negative_test "Test 13: Invalid option" \
  --windows-target-name "windows-11" \
  --invalid-option "value"

echo ""
echo "=== JSON Structure Tests ==="

if command -v jq &> /dev/null; then
  # Test JSON structure
  "$SCRIPT_PATH" --windows-target-name "windows-11" > /dev/null 2>&1
  
  echo ""
  echo "Validating JSON structure..."
  
  # Check if JSON is valid
  if jq empty ./windows-iso-config.json 2>/dev/null; then
    print_result "Test 14: JSON is valid" "PASS"
  else
    print_result "Test 14: JSON is valid" "FAIL" "Invalid JSON format"
  fi
  
  # Check if all required keys exist
  # NOTE: We use jq's 'has()' function instead of 'jq -e .$key' because 
  # 'jq -e' treats boolean false values as "falsy" and returns exit code 1,
  # which would incorrectly report that keys with false values are missing.
  required_keys=("windowsTargetName" "destinationDirectory" "architecture" "arch" "edition" "lang" "esd" "drivers" "netfx3" "preview" "ringLower" "targets")
  
  all_keys_exist=true
  for key in "${required_keys[@]}"; do
    # Use 'has' to check key existence regardless of value (including false)
    result=$(jq "has(\"$key\")" ./windows-iso-config.json 2>/dev/null)
    if [[ "$result" != "true" ]]; then
      echo "  Missing key: $key"
      all_keys_exist=false
    fi
  done
  
  if $all_keys_exist; then
    print_result "Test 15: All required keys exist" "PASS"
  else
    print_result "Test 15: All required keys exist" "FAIL"
  fi
  
  # Check targets structure
  target_keys=("windows-10" "windows-11old" "windows-11" "windows-11new" "windows-11beta" "windows-11dev" "windows-11canary")
  
  all_targets_exist=true
  for target in "${target_keys[@]}"; do
    if ! jq -e ".targets.\"$target\"" ./windows-iso-config.json > /dev/null 2>&1; then
      echo "  Missing target: $target"
      all_targets_exist=false
    fi
  done
  
  if $all_targets_exist; then
    print_result "Test 16: All target definitions exist" "PASS"
  else
    print_result "Test 16: All target definitions exist" "FAIL"
  fi
  
  # Verify target structure (each target should have search and edition)
  all_targets_valid=true
  for target in "${target_keys[@]}"; do
    if ! jq -e ".targets.\"$target\".search" ./windows-iso-config.json > /dev/null 2>&1; then
      echo "  Target $target missing 'search' field"
      all_targets_valid=false
    fi
    if ! jq -e ".targets.\"$target\".edition" ./windows-iso-config.json > /dev/null 2>&1; then
      echo "  Target $target missing 'edition' field"
      all_targets_valid=false
    fi
  done
  
  if $all_targets_valid; then
    print_result "Test 17: All targets have required fields" "PASS"
  else
    print_result "Test 17: All targets have required fields" "FAIL"
  fi
  
else
  echo -e "${YELLOW}jq not installed - skipping JSON structure validation${NC}"
  echo -e "${YELLOW}Install jq for complete testing: apt-get install jq or brew install jq${NC}"
fi

# Clean up
rm -f ./windows-iso-config.json

echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Total tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
fi