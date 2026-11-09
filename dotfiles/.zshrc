# Managed by ~/Code/jessegeens/install.sh -- edit the copy in the repo.
# TODO: replace with the oh-my-zsh .zshrc from the laptop.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)

source "$ZSH/oh-my-zsh.sh"

# PATH
export PATH="$HOME/.local/bin:$PATH"
[[ -d /usr/local/go/bin ]] && export PATH="$PATH:/usr/local/go/bin"
command -v go >/dev/null && export PATH="$PATH:$(go env GOPATH)/bin"

export EDITOR=nvim
export VISUAL=nvim

# fzf (needs fzf >= 0.48 for --zsh)
command -v fzf >/dev/null && source <(fzf --zsh)

# Syntax highlighting (same path on Fedora and Debian; must be sourced late)
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
if [[ -d "$PYENV_ROOT/bin" ]]; then
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init - zsh)"
fi

# Aliases
alias zshconfig="nvim ~/.zshrc"
[[ -f ~/.aliases ]] && source ~/.aliases

# Machine-specific settings that should not live in the repo
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
