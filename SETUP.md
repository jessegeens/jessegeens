# Machine setup

Scripts and dotfiles to turn a fresh Linux install into my working environment.

## Quick start

On a new machine, as your normal user (not root):

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jessegeens/jessegeens/main/bootstrap.sh)"
```

This installs git if needed, clones this repo to `~/Code/jessegeens` and runs
`install.sh`. Log out and back in afterwards to get zsh as your shell.

For a server, VM or WSL without a desktop, skip the GUI apps:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jessegeens/jessegeens/main/bootstrap.sh)" -- --no-gui
```

The clone uses HTTPS. Once your SSH key is on GitHub, switch to SSH so you can push:

```sh
git -C ~/Code/jessegeens remote set-url origin git@github.com:jessegeens/jessegeens.git
```

## Supported systems

| Family | Tested on | Package manager |
| --- | --- | --- |
| Fedora-like | Fedora 44 | dnf |
| Debian-like | Debian 12, Ubuntu 24.04 (and derivatives such as Mint) | apt |

The scripts don't support immutable Fedora (Silverblue, Kinoite, Bazzite) or
RHEL clones.

## What `install.sh` does

1. **Detects the distro** from `/etc/os-release`.
2. **Sets up repositories.**
   - Fedora: RPM Fusion (free + nonfree), Cisco OpenH264, full multimedia
     codecs, and the VS Code repo.
   - Debian/Ubuntu: GitHub CLI, Tailscale, VS Code and Mozilla (Firefox).
3. **Installs packages** from the lists in [`packages/`](packages):

   | File | Contents |
   | --- | --- |
   | `fedora.txt`, `debian.txt` | CLI and dev tools |
   | `fedora-gui.txt`, `debian-gui.txt` | Desktop apps |
   | `flatpak.txt` | Flathub apps for every distro (Signal, Obsidian) |
   | `flatpak-debian.txt` | Flathub apps for Debian/Ubuntu only (Thunderbird) |

   Tools that the distros don't package, or only package old versions of,
   come from upstream:
   - zellij on every distro;
   - Neovim, fzf and Go on Debian/Ubuntu.
4. **Enables `tailscaled`.** Run `sudo tailscale up` once to log in.
5. **Installs oh-my-zsh, symlinks the dotfiles and makes zsh the login shell.**

The script is idempotent, so re-run it after changing a package list or
adding a dotfile.

### Options

| Flag | Effect |
| --- | --- |
| `--no-gui` | Skip GUI packages and Flatpaks |
| `--dotfiles-only` | Only install oh-my-zsh and (re)link the dotfiles |

## Dotfiles

Everything in [`dotfiles/`](dotfiles) mirrors its location under `$HOME`:

| Repo path | Linked to |
| --- | --- |
| `dotfiles/.zshrc` | `~/.zshrc` |
| `dotfiles/.aliases` | `~/.aliases` |
| `dotfiles/.gitconfig` | `~/.gitconfig` |
| `dotfiles/.config/zellij/` | `~/.config/zellij/` |
| `dotfiles/.config/nvim/` | `~/.config/nvim/` |

- **Symlinks:** the files are symlinked rather than copied, so editing
  `~/.zshrc` edits the repo. Commit the changes to keep machines in sync.
- **Backups:** any file that would be replaced is moved to
  `~/.dotfiles-backup/<timestamp>/` first.
- **Missing entries:** an entry that doesn't exist in the repo yet is skipped
  with a warning.
- **Machine-specific shell settings** (SDK paths, work-only exports) go in
  `~/.zshrc.local`. The `.zshrc` sources that file if it exists, and it is not
  tracked.

### Adding a new dotfile

1. Move the file into `dotfiles/`, keeping its path relative to `$HOME`.
2. Add that path to the `DOTFILES` array at the top of `install.sh`.
3. Run `./install.sh --dotfiles-only`.
