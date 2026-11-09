#!/usr/bin/env bash
# Set up a fresh Linux machine: repositories, packages, tools and dotfiles.
#
# Supported: Fedora-like (dnf) and Debian/Ubuntu-like (apt).
#
# Usage:
#   git clone https://github.com/jessegeens/jessegeens ~/Code/jessegeens
#   ~/Code/jessegeens/install.sh [--no-gui] [--dotfiles-only]
#
#   --no-gui         skip GUI apps and Flatpaks (servers, VMs, WSL)
#   --dotfiles-only  only install oh-my-zsh and link the dotfiles
#
# Dotfiles are symlinked from this repo, so keep the clone where it is.
# Existing files are moved to ~/.dotfiles-backup/<timestamp>/ first.
# The script is idempotent: re-run it whenever the lists or dotfiles change.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"
PACKAGES_DIR="$REPO_DIR/packages"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# Paths relative to $HOME (and to dotfiles/) that get symlinked.
# Entries that don't exist in the repo yet are skipped.
DOTFILES=(
    .zshrc
    .aliases
    .gitconfig
    .config/zellij
    .config/nvim
)

WITH_GUI=1
DOTFILES_ONLY=0
NOTES=()

# --- helpers -----------------------------------------------------------------

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Print the package names in a list file, without comments or blank lines.
read_list() {
    [[ -f "$1" ]] || return 0
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | awk 'NF { print $1 }'
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

download() { curl -fsSL --retry 3 -o "$2" "$1"; }

# --- distro detection --------------------------------------------------------

detect_distro() {
    [[ -r /etc/os-release ]] || die "/etc/os-release not found; cannot detect distro"
    # shellcheck disable=SC1091
    . /etc/os-release
    local ids=" ${ID:-} ${ID_LIKE:-} "

    if [[ "$ids" == *" fedora "* ]]; then
        FAMILY=fedora
        [[ -e /run/ostree-booted ]] &&
            die "Immutable Fedora (Silverblue/Kinoite/Bazzite) is not supported: use rpm-ostree"
        # The RPM Fusion setup below relies on %fedora, which RHEL clones don't define.
        [[ "$(rpm -E %fedora)" =~ ^[0-9]+$ ]] ||
            die "$NAME looks like RHEL/EL rather than Fedora; not supported yet"
    elif [[ "$ids" == *" debian "* || "$ids" == *" ubuntu "* ]]; then
        FAMILY=debian
        # Ubuntu derivatives (Mint, Pop!_OS, ...) set UBUNTU_CODENAME.
        if [[ -n "${UBUNTU_CODENAME:-}" ]]; then
            APT_DIST=ubuntu
            APT_CODENAME=$UBUNTU_CODENAME
        else
            APT_DIST=debian
            APT_CODENAME=${VERSION_CODENAME:?VERSION_CODENAME missing from /etc/os-release}
        fi
    else
        die "Unsupported distro: ${PRETTY_NAME:-$ID} (ID=$ID, ID_LIKE=${ID_LIKE:-})"
    fi

    case "$(uname -m)" in
        x86_64)  ARCH_GNU=x86_64;  ARCH_GO=amd64 ;;
        aarch64) ARCH_GNU=aarch64; ARCH_GO=arm64 ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac

    log "Detected ${PRETTY_NAME:-$ID} ($FAMILY family, $(uname -m))"
}

# --- Fedora ------------------------------------------------------------------

dnf_is_5() { dnf --version 2>/dev/null | grep -q 'dnf5'; }

fedora_setup_repos() {
    log "Setting up Fedora repositories"
    local fedora_ver
    fedora_ver="$(rpm -E %fedora)"

    if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
        log "Enabling RPM Fusion (free + nonfree)"
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    fi

    log "Enabling the Cisco OpenH264 repo"
    if dnf_is_5; then
        sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
    else
        sudo dnf config-manager --set-enabled fedora-cisco-openh264
    fi

    if [[ $WITH_GUI -eq 1 && ! -f /etc/yum.repos.d/vscode.repo ]]; then
        log "Adding the Visual Studio Code repo"
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    fi

    sudo dnf makecache -y
}

fedora_multimedia() {
    log "Installing full multimedia codecs from RPM Fusion"
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
        sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    fi
    # Install the group first: `update @multimedia` fails if it isn't installed
    # yet (e.g. minimal/Server installs). Both are no-ops when up to date.
    local opts=(--setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin)
    sudo dnf group install -y multimedia --allowerasing "${opts[@]}"
    sudo dnf update -y @multimedia "${opts[@]}"
}

fedora_install_packages() {
    local pkgs
    mapfile -t pkgs < <(read_list "$PACKAGES_DIR/fedora.txt")
    if [[ $WITH_GUI -eq 1 ]]; then
        mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$PACKAGES_DIR/fedora-gui.txt")
    fi
    log "Installing ${#pkgs[@]} packages with dnf"
    sudo dnf install -y "${pkgs[@]}"
    fedora_multimedia
}

# --- Debian / Ubuntu ---------------------------------------------------------

apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }

debian_setup_repos() {
    log "Setting up apt repositories"
    sudo apt-get update
    apt_install ca-certificates curl gnupg
    sudo install -d -m 0755 /etc/apt/keyrings

    local arch
    arch="$(dpkg --print-architecture)"

    if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
        log "Adding the GitHub CLI repo"
        download https://cli.github.com/packages/githubcli-archive-keyring.gpg "$TMP_DIR/gh.gpg"
        sudo install -m 0644 "$TMP_DIR/gh.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
            sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    fi

    if [[ ! -f /etc/apt/sources.list.d/tailscale.list ]]; then
        log "Adding the Tailscale repo ($APT_DIST/$APT_CODENAME)"
        download "https://pkgs.tailscale.com/stable/$APT_DIST/$APT_CODENAME.noarmor.gpg" "$TMP_DIR/ts.gpg"
        sudo install -m 0644 "$TMP_DIR/ts.gpg" /usr/share/keyrings/tailscale-archive-keyring.gpg
        download "https://pkgs.tailscale.com/stable/$APT_DIST/$APT_CODENAME.tailscale-keyring.list" "$TMP_DIR/ts.list"
        sudo install -m 0644 "$TMP_DIR/ts.list" /etc/apt/sources.list.d/tailscale.list
    fi

    if [[ $WITH_GUI -eq 1 ]]; then
        if [[ ! -f /etc/apt/sources.list.d/vscode.sources && ! -f /etc/apt/sources.list.d/vscode.list ]]; then
            log "Adding the Visual Studio Code repo"
            download https://packages.microsoft.com/keys/microsoft.asc "$TMP_DIR/ms.asc"
            gpg --dearmor <"$TMP_DIR/ms.asc" >"$TMP_DIR/microsoft.gpg"
            sudo install -m 0644 "$TMP_DIR/microsoft.gpg" /usr/share/keyrings/microsoft.gpg
            sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
        fi

        # Debian only ships firefox-esr and Ubuntu ships a snap: use Mozilla's repo.
        if [[ ! -f /etc/apt/sources.list.d/mozilla.list ]]; then
            log "Adding the Mozilla (Firefox) repo"
            download https://packages.mozilla.org/apt/repo-signing-key.gpg "$TMP_DIR/mozilla.asc"
            sudo install -m 0644 "$TMP_DIR/mozilla.asc" /etc/apt/keyrings/packages.mozilla.org.asc
            echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" |
                sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
            sudo tee /etc/apt/preferences.d/mozilla >/dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
        fi
    fi

    sudo apt-get update
}

debian_install_packages() {
    local pkgs
    mapfile -t pkgs < <(read_list "$PACKAGES_DIR/debian.txt")
    if [[ $WITH_GUI -eq 1 ]]; then
        mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$PACKAGES_DIR/debian-gui.txt")
    fi
    log "Installing ${#pkgs[@]} packages with apt"
    apt_install "${pkgs[@]}"

    # Debian renames these binaries to avoid name clashes.
    mkdir -p "$HOME/.local/bin"
    [[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
    [[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
    return 0
}

# The apt versions of these are too old (e.g. `fzf --zsh` needs fzf >= 0.48,
# and most nvim plugin managers need nvim >= 0.10).
debian_install_upstream() {
    # Check /opt/nvim rather than `have nvim`: python3-pynvim drags in the old
    # apt neovim. /usr/local/bin/nvim shadows it in PATH.
    if [[ ! -x /opt/nvim/bin/nvim ]]; then
        log "Installing Neovim (latest release) to /opt/nvim"
        local nvim_arch=$ARCH_GNU
        [[ $nvim_arch == aarch64 ]] && nvim_arch=arm64
        download "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz" "$TMP_DIR/nvim.tar.gz"
        sudo rm -rf /opt/nvim
        sudo mkdir -p /opt/nvim
        sudo tar -C /opt/nvim --strip-components=1 -xzf "$TMP_DIR/nvim.tar.gz"
        sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
    fi

    # ~/.local/bin may not be on PATH yet, so check our own install explicitly.
    local fzf_bin="$HOME/.fzf/bin/fzf"
    [[ -x "$fzf_bin" ]] || fzf_bin="$(command -v fzf || true)"
    if [[ -z "$fzf_bin" ]] || ! "$fzf_bin" --zsh >/dev/null 2>&1; then
        log "Installing fzf (latest release) to ~/.fzf"
        if [[ -d "$HOME/.fzf/.git" ]]; then
            git -C "$HOME/.fzf" pull --ff-only
        else
            git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        fi
        "$HOME/.fzf/install" --bin
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
    fi

    if ! have go && [[ ! -x /usr/local/go/bin/go ]]; then
        local go_version
        go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
        log "Installing $go_version to /usr/local/go"
        download "https://go.dev/dl/${go_version}.linux-${ARCH_GO}.tar.gz" "$TMP_DIR/go.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "$TMP_DIR/go.tar.gz"
    fi
}

# --- common ------------------------------------------------------------------

install_zellij() {
    have zellij && return 0
    log "Installing zellij (latest release) to /usr/local/bin"
    download "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${ARCH_GNU}-unknown-linux-musl.tar.gz" "$TMP_DIR/zellij.tar.gz"
    tar -C "$TMP_DIR" -xzf "$TMP_DIR/zellij.tar.gz" zellij
    sudo install -m 0755 "$TMP_DIR/zellij" /usr/local/bin/zellij
}

install_flatpaks() {
    local apps
    mapfile -t apps < <(read_list "$PACKAGES_DIR/flatpak.txt")
    if [[ $FAMILY == debian ]]; then
        mapfile -t -O "${#apps[@]}" apps < <(read_list "$PACKAGES_DIR/flatpak-debian.txt")
    fi
    [[ ${#apps[@]} -gt 0 ]] || return 0

    log "Installing ${#apps[@]} Flatpaks from Flathub"
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    # Fedora ships Flathub disabled/filtered; make the full catalogue available.
    sudo flatpak remote-modify --enable --no-filter flathub
    sudo flatpak install -y --noninteractive flathub "${apps[@]}"
}

enable_services() {
    if systemctl list-unit-files tailscaled.service >/dev/null 2>&1; then
        log "Enabling tailscaled"
        sudo systemctl enable --now tailscaled
        if ! tailscale status >/dev/null 2>&1; then
            NOTES+=("Log in to Tailscale: sudo tailscale up")
        fi
    fi
}

install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log "oh-my-zsh already installed"
        return
    fi
    log "Installing oh-my-zsh"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
}

link_dotfiles() {
    log "Linking dotfiles from $DOTFILES_DIR"
    local rel src dst
    for rel in "${DOTFILES[@]}"; do
        src="$DOTFILES_DIR/$rel"
        dst="$HOME/$rel"

        if [[ ! -e "$src" ]]; then
            warn "skipping ~/$rel: not in the repo yet ($src)"
            continue
        fi
        if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
            echo "    ok      ~/$rel"
            continue
        fi
        if [[ -e "$dst" || -L "$dst" ]]; then
            mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
            mv "$dst" "$BACKUP_DIR/$rel"
            echo "    backup  ~/$rel -> $BACKUP_DIR/$rel"
        fi
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        echo "    linked  ~/$rel"
    done
}

set_default_shell() {
    local zsh_path current
    zsh_path="$(command -v zsh)" || { warn "zsh not installed; not changing the login shell"; return; }
    current="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current" != "$zsh_path" ]]; then
        log "Changing the login shell to $zsh_path"
        sudo usermod -s "$zsh_path" "$USER"
        NOTES+=("Log out and back in to start using zsh")
    fi
}

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

# --- main --------------------------------------------------------------------

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-gui) WITH_GUI=0 ;;
            --dotfiles-only) DOTFILES_ONLY=1 ;;
            -h|--help) usage; exit 0 ;;
            *) usage; die "unknown option: $1" ;;
        esac
        shift
    done

    [[ $EUID -ne 0 ]] || die "Run this as your normal user, not root (sudo is used where needed)"

    if [[ $DOTFILES_ONLY -eq 0 ]]; then
        detect_distro
        sudo -v   # ask for the password once, up front

        case "$FAMILY" in
            fedora)
                fedora_setup_repos
                fedora_install_packages
                ;;
            debian)
                debian_setup_repos
                debian_install_packages
                debian_install_upstream
                ;;
        esac

        install_zellij
        [[ $WITH_GUI -eq 1 ]] && install_flatpaks
        enable_services
    fi

    have git || die "git is required to install oh-my-zsh"
    install_oh_my_zsh
    link_dotfiles
    [[ $DOTFILES_ONLY -eq 1 ]] || set_default_shell

    log "Done!"
    [[ -d "$BACKUP_DIR" ]] && echo "    Replaced files were backed up to $BACKUP_DIR"
    local note
    for note in "${NOTES[@]}"; do echo "  - $note"; done
}

main "$@"
