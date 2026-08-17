export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)

# mise activation
eval "$(/usr/local/bin/mise activate zsh)"

# Optional project detection on cd. Disabled by default; use init-project for
# explicit initialization, or set WORKSPACE_AUTO_DETECT=true for opt-in mode.
detect_stack_on_cd() {
  [ "${WORKSPACE_AUTO_DETECT:-false}" != "true" ] && return
  [ "${MISED_SKIP_DETECT:-0}" = "1" ] && return
  [ -f .mise.toml ] || [ -f .tool-versions ] && return
  command -v detect-stack >/dev/null 2>&1 || return
  detect-stack . >/dev/null 2>&1
}
chpwd_functions+=(detect_stack_on_cd)

# homebrew shellenv
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; fi
source "$ZSH/oh-my-zsh.sh"
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
