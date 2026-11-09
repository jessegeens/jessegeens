#!/usr/bin/env bash
# Bootstrap a new machine: install git, clone this repo, run install.sh.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jessegeens/jessegeens/main/bootstrap.sh)"
#
# Extra arguments are passed on to install.sh, e.g.:
#   bash -c "$(curl -fsSL .../bootstrap.sh)" -- --no-gui
#
# Override the clone location / branch with REPO_DIR=... BRANCH=...

set -euo pipefail

REPO_URL="https://github.com/jessegeens/jessegeens.git"
REPO_DIR="${REPO_DIR:-$HOME/Code/jessegeens}"
BRANCH="${BRANCH:-main}"

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root" >&2; exit 1; }

if ! command -v git >/dev/null 2>&1; then
    echo "==> Installing git"
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y git
    else
        echo "No dnf or apt-get found; install git manually" >&2
        exit 1
    fi
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    echo "==> Updating $REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only
else
    echo "==> Cloning into $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

exec "$REPO_DIR/install.sh" "$@"
