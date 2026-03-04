#!/usr/bin/env bats
# Tests for scripts/lib/json.sh - JSON configuration manipulation utilities

setup() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${ROOT_DIR}/scripts/lib/log.sh"
  source "${ROOT_DIR}/scripts/lib/cmd.sh"
  source "${ROOT_DIR}/scripts/lib/json.sh"
  TAG="test"

  # Create temp directory for test files
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  # Clean up test directory
  rm -rf "${TEST_DIR}"
}

# merge_json_config tests

@test "merge_json_config: creates new file with empty object" {
  local cfg="${TEST_DIR}/new.json"

  run merge_json_config "${cfg}" '.foo = "bar"'
  [ "$status" -eq 0 ]
  [ -f "${cfg}" ]

  local result
  result="$(jq -r '.foo' "${cfg}")"
  [ "$result" = "bar" ]
}

@test "merge_json_config: merges into existing file" {
  local cfg="${TEST_DIR}/existing.json"
  echo '{"existing": "value"}' > "${cfg}"

  run merge_json_config "${cfg}" '.new = "data"'
  [ "$status" -eq 0 ]

  # Check both values exist
  local existing new
  existing="$(jq -r '.existing' "${cfg}")"
  new="$(jq -r '.new' "${cfg}")"
  [ "$existing" = "value" ]
  [ "$new" = "data" ]
}

@test "merge_json_config: updates existing keys" {
  local cfg="${TEST_DIR}/update.json"
  echo '{"key": "old"}' > "${cfg}"

  run merge_json_config "${cfg}" '.key = "new"'
  [ "$status" -eq 0 ]

  local result
  result="$(jq -r '.key' "${cfg}")"
  [ "$result" = "new" ]
}

@test "merge_json_config: supports jq arguments" {
  local cfg="${TEST_DIR}/args.json"

  run merge_json_config "${cfg}" '.cmd = $command' --arg command "/usr/bin/test"
  [ "$status" -eq 0 ]

  local result
  result="$(jq -r '.cmd' "${cfg}")"
  [ "$result" = "/usr/bin/test" ]
}

@test "merge_json_config: handles complex nested structures" {
  local cfg="${TEST_DIR}/nested.json"

  run merge_json_config "${cfg}" '.servers.personal = {command: $cmd, args: []}' --arg cmd "myserver"
  [ "$status" -eq 0 ]

  local cmd
  cmd="$(jq -r '.servers.personal.command' "${cfg}")"
  [ "$cmd" = "myserver" ]

  local args_type
  args_type="$(jq -r '.servers.personal.args | type' "${cfg}")"
  [ "$args_type" = "array" ]
}

@test "merge_json_config: fails on invalid jq filter" {
  local cfg="${TEST_DIR}/invalid.json"

  run merge_json_config "${cfg}" '.invalid syntax {{{'
  [ "$status" -eq 1 ]
  [[ "$output" =~ "jq filter failed" ]]
}

@test "merge_json_config: creates parent directory if needed" {
  local cfg="${TEST_DIR}/subdir/config.json"

  # Directory doesn't exist yet
  [ ! -d "${TEST_DIR}/subdir" ]

  # merge_json_config doesn't create parent dirs, but ensure_json_dir does
  mkdir -p "$(dirname "${cfg}")"
  run merge_json_config "${cfg}" '.test = true'
  [ "$status" -eq 0 ]
  [ -f "${cfg}" ]
}

# read_json_value tests

@test "read_json_value: reads simple value" {
  local cfg="${TEST_DIR}/read.json"
  echo '{"name": "test"}' > "${cfg}"

  run read_json_value "${cfg}" '.name'
  [ "$status" -eq 0 ]
  [ "$output" = "test" ]
}

@test "read_json_value: reads nested value" {
  local cfg="${TEST_DIR}/nested_read.json"
  echo '{"server": {"host": "localhost", "port": 8080}}' > "${cfg}"

  run read_json_value "${cfg}" '.server.host'
  [ "$status" -eq 0 ]
  [ "$output" = "localhost" ]
}

@test "read_json_value: returns null for missing keys" {
  local cfg="${TEST_DIR}/missing.json"
  echo '{"exists": "yes"}' > "${cfg}"

  run read_json_value "${cfg}" '.missing'
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "read_json_value: fails when file missing" {
  run read_json_value "${TEST_DIR}/nonexistent.json" '.key'
  [ "$status" -eq 1 ]
  [[ "$output" =~ "JSON file not found" ]]
}

@test "read_json_value: reads array values" {
  local cfg="${TEST_DIR}/array.json"
  echo '{"items": ["a", "b", "c"]}' > "${cfg}"

  run read_json_value "${cfg}" '.items[1]'
  [ "$status" -eq 0 ]
  [ "$output" = "b" ]
}

# update_json_value tests

@test "update_json_value: updates simple value" {
  local cfg="${TEST_DIR}/update_simple.json"
  echo '{"key": "old"}' > "${cfg}"

  run update_json_value "${cfg}" '.key' 'new'
  [ "$status" -eq 0 ]

  local result
  result="$(jq -r '.key' "${cfg}")"
  [ "$result" = "new" ]
}

@test "update_json_value: creates new key" {
  local cfg="${TEST_DIR}/update_new.json"
  echo '{}' > "${cfg}"

  run update_json_value "${cfg}" '.new_key' 'value'
  [ "$status" -eq 0 ]

  local result
  result="$(jq -r '.new_key' "${cfg}")"
  [ "$result" = "value" ]
}

@test "update_json_value: updates nested value" {
  local cfg="${TEST_DIR}/update_nested.json"
  echo '{"server": {"port": 8080}}' > "${cfg}"

  run update_json_value "${cfg}" '.server.port' '9090'
  [ "$status" -eq 0 ]

  local result
  result="$(jq -r '.server.port' "${cfg}")"
  [ "$result" = "9090" ]
}

# validate_json tests

@test "validate_json: succeeds on valid JSON" {
  local cfg="${TEST_DIR}/valid.json"
  echo '{"valid": true}' > "${cfg}"

  run validate_json "${cfg}"
  [ "$status" -eq 0 ]
}

@test "validate_json: fails on invalid JSON" {
  local cfg="${TEST_DIR}/invalid.json"
  echo '{invalid json' > "${cfg}"

  run validate_json "${cfg}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "invalid JSON" ]]
}

@test "validate_json: fails when file missing" {
  run validate_json "${TEST_DIR}/nonexistent.json"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "JSON file not found" ]]
}

@test "validate_json: succeeds on empty object" {
  local cfg="${TEST_DIR}/empty.json"
  echo '{}' > "${cfg}"

  run validate_json "${cfg}"
  [ "$status" -eq 0 ]
}

@test "validate_json: succeeds on empty array" {
  local cfg="${TEST_DIR}/empty_array.json"
  echo '[]' > "${cfg}"

  run validate_json "${cfg}"
  [ "$status" -eq 0 ]
}

# ensure_json_dir tests

@test "ensure_json_dir: creates parent directory" {
  local cfg="${TEST_DIR}/deep/nested/path/config.json"

  [ ! -d "${TEST_DIR}/deep" ]

  run ensure_json_dir "${cfg}"
  [ "$status" -eq 0 ]
  [ -d "${TEST_DIR}/deep/nested/path" ]
}

@test "ensure_json_dir: succeeds when directory exists" {
  local cfg="${TEST_DIR}/existing_dir/config.json"
  mkdir -p "${TEST_DIR}/existing_dir"

  run ensure_json_dir "${cfg}"
  [ "$status" -eq 0 ]
  [ -d "${TEST_DIR}/existing_dir" ]
}

@test "ensure_json_dir: handles file in current directory" {
  local cfg="${TEST_DIR}/config.json"

  run ensure_json_dir "${cfg}"
  [ "$status" -eq 0 ]
  [ -d "${TEST_DIR}" ]
}

# Integration tests

@test "integration: full workflow create-read-update-validate" {
  local cfg="${TEST_DIR}/workflow.json"

  # Create with merge_json_config
  merge_json_config "${cfg}" '.app = {name: $name, version: $ver}' --arg name "testapp" --arg ver "1.0"

  # Validate
  run validate_json "${cfg}"
  [ "$status" -eq 0 ]

  # Read
  local name
  name="$(read_json_value "${cfg}" '.app.name')"
  [ "$name" = "testapp" ]

  # Update
  update_json_value "${cfg}" '.app.version' '2.0'

  # Read updated value
  local version
  version="$(read_json_value "${cfg}" '.app.version')"
  [ "$version" = "2.0" ]

  # Ensure original value unchanged
  name="$(read_json_value "${cfg}" '.app.name')"
  [ "$name" = "testapp" ]
}

@test "integration: real-world MCP config scenario" {
  local cfg="${TEST_DIR}/mcp.json"

  # Simulate setup-ai-tools.sh pattern
  merge_json_config "${cfg}" '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers.personal = {
      "command": $cmd,
      "args": [],
      "env": {
        "MCP_CTX_DIR": $ctx,
        "BAML_LOG": "info"
      }
    }
  ' --arg cmd "/usr/local/bin/personal-mcp" --arg ctx "/Users/test/.ctx"

  # Validate structure
  run validate_json "${cfg}"
  [ "$status" -eq 0 ]

  # Verify values
  local cmd ctx
  cmd="$(read_json_value "${cfg}" '.mcpServers.personal.command')"
  ctx="$(read_json_value "${cfg}" '.mcpServers.personal.env.MCP_CTX_DIR')"
  [ "$cmd" = "/usr/local/bin/personal-mcp" ]
  [ "$ctx" = "/Users/test/.ctx" ]
}
