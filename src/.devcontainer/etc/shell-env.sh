# Loads every *.sh fragment in /etc/shell-env.d into the current shell.
#
# The directory is the contract: drop a file in, it lands in your environment.
# The Containerfile handles hooking this loader into each shell's startup path;
# nothing outside the image build needs to know which hook fired. The path is
# fixed because devcontainer.json mounts a volume at it — a configurable path
# could drift from the mount and silently stop persisting.
#
# Fragments must be export-only and silent. This is sourced by non-interactive
# shells, so anything a fragment prints lands inside the $(...) capture of
# unrelated scripts.
if [ -n "${SHELL_ENV_LOADED:-}" ]; then
  return 0
fi
export SHELL_ENV_LOADED=1

if [ -d /etc/shell-env.d ]; then
  for _fragment in /etc/shell-env.d/*.sh; do
    # shellcheck source=/dev/null
    [ -r "$_fragment" ] && . "$_fragment"
  done
  unset _fragment
fi
