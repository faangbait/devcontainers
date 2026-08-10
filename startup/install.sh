#!/bin/bash
set -e
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

(
  cd /usr/local/share/
  sudo ln -sf "${DOTFILES_DIR}/.gitignore_global"
  echo "Dotfiles successfully installed! $(pwd)"
)
