# DevContainer Startup Dotfiles

This is one way to inject dotfiles from your host without a bind mount. I've toyed with it a bit. It works okay? I think my verdict is "not worth," but I kept it here for posterity.

This has to be installed in your USER SETTINGS (host config).

{
  "dev.containers.copyGitConfig": true,
  "dotfiles.installCommand": "~/.config/git/startup/install.sh",
  "dotfiles.repository": "https://github.com/faangbait/devcontainers.git",
  "dotfiles.targetPath": "~/.config/git",
}
