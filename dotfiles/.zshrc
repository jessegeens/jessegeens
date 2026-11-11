# Managed by ~/Code/jessegeens/install.sh -- edit the copy in the repo.
# Machine-specific settings go in ~/.zshrc.local (sourced at the end).

# Deno completions (must be on FPATH before oh-my-zsh runs compinit)
if [[ -d "$HOME/.zsh/completions" && ":$FPATH:" != *":$HOME/.zsh/completions:"* ]]; then
  export FPATH="$HOME/.zsh/completions:$FPATH"
fi

# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"   # needs a Powerline or Nerd Font in the terminal
plugins=(git)
# Not part of oh-my-zsh: install.sh clones it into $ZSH_CUSTOM/plugins.
[[ -d "${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-syntax-highlighting" ]] &&
  plugins+=(zsh-syntax-highlighting)
[[ -r "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi
export VISUAL="$EDITOR"

# PATH
export PATH="$HOME/.local/bin:$PATH"
export GOPATH="$HOME/.go"
export PATH="$PATH:$GOPATH/bin"
[[ -d /usr/local/go/bin ]] && export PATH="$PATH:/usr/local/go/bin"

# fzf (needs fzf >= 0.48 for --zsh)
command -v fzf >/dev/null && source <(fzf --zsh 2>/dev/null)

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null; then
  eval "$(pyenv init -)"
  [[ -d "$PYENV_ROOT/plugins/pyenv-virtualenv" ]] && eval "$(pyenv virtualenv-init -)"
fi

# deno
[[ -f "$HOME/.deno/env" ]] && source "$HOME/.deno/env"

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# pnpm
if [[ -d "$HOME/.local/share/pnpm" ]]; then
  export PNPM_HOME="$HOME/.local/share/pnpm"
  case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac
fi

# opencode
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

# Aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# Machine-specific settings that should not live in the repo
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
