#!/bin/bash
set -euo pipefail

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/project"
touch "$test_root/project/package.json" \
  "$test_root/project/requirements.txt" \
  "$test_root/project/dev_requirements.txt"

cat > "$test_root/bin/npm" <<EOF
#!/bin/sh
printf 'npm %s\n' "\$*" >> "$test_root/calls"
EOF
cat > "$test_root/bin/python" <<EOF
#!/bin/sh
printf 'python %s\n' "\$*" >> "$test_root/calls"
EOF
chmod +x "$test_root/bin/npm" "$test_root/bin/python"

env -u CLAUDE_CONFIG_DIR PATH="$test_root/bin:$PATH" \
  PROJECT_ROOT="$test_root/project" bash "$(dirname "$0")/post-create.sh"

grep -qxF "npm --prefix $test_root/project install" "$test_root/calls"
grep -qxF "python -m pip install -r $test_root/project/requirements.txt -r $test_root/project/dev_requirements.txt" "$test_root/calls"
