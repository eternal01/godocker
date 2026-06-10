#--------------------------------------------------------------------------
# Base Development Workspace
#--------------------------------------------------------------------------
# 职责：提供 100% 通用的开发"壳"，不含任何语言运行时
# 语言运行时通过 mise 在构建时或启动时按需安装
#--------------------------------------------------------------------------

ARG SYSTEM_NAME=debian
ARG SYSTEM_VERSION=bookworm
FROM ${SYSTEM_NAME}:${SYSTEM_VERSION}

LABEL maintainer="muxk <361087696@qq.com>"
LABEL description="Base development workspace with mise, homebrew, zsh"

ENV DEBIAN_FRONTEND=noninteractive

USER root

###########################################################################
# Build Arguments & Environment
###########################################################################

ARG TZ=UTC
ARG PUID=1000
ARG PGID=1000
ARG WORKSPACE_USER=developer
ARG WORKSPACE_HOME=/home/developer
ARG WORKSPACE_PATH=/workspace

ARG WORKSPACE_INSTALL_DNSUTILS=false
ARG WORKSPACE_INSTALL_WORKSPACE_SSH=false
ARG WORKSPACE_INSTALL_BREW=true
ARG WORKSPACE_BREW_PACKAGES="jq yq ripgrep fzf tree tmux fd neovim"

# mise pre-installed languages at build time (e.g. "go@1.22.4 rust@stable php@8.3.6")
ARG WORKSPACE_PREINSTALL_LANGUAGES=""
# Pin mise to a specific release. The literal "latest" does NOT work — the
# installer concatenates the value directly into the GitHub release URL, so
# "latest" produces /releases/download/vlatest/... which 404s. To upgrade,
# bump this line and rebuild.
ARG MISE_VERSION=v2026.6.1

# Proxy support: declared as ARG, exported as ENV (both upper- and lower-case so
# apt, curl, go, and pip all pick it up). Leave HTTP_PROXY empty in .env to
# disable. The compose file passes these as build args and uses
# `build.network: host` so 127.0.0.1:port inside the build container resolves
# to the host's proxy.
ARG HTTP_PROXY=
ARG HTTPS_PROXY=
ARG NO_PROXY=localhost,127.0.0.1,::1,.local

ENV TZ=${TZ}
ENV WORKSPACE_USER=${WORKSPACE_USER}
ENV WORKSPACE_HOME=${WORKSPACE_HOME}
ENV WORKSPACE_PATH=${WORKSPACE_PATH}

ENV HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY}

# mise paths (shims will be added to PATH by mise activate)
ENV MISE_DATA_DIR=${WORKSPACE_HOME}/.local/share/mise
ENV MISE_CONFIG_DIR=${WORKSPACE_HOME}/.config/mise
ENV MISE_CACHE_DIR=${WORKSPACE_HOME}/.cache/mise
# Auto-install missing tools the first time a project directory is entered.
# Pairs with the chpwd hook that runs `detect-stack .` so freshly-cloned
# projects get their .mise.toml + installed toolchain without any manual step.
ENV MISE_AUTO_INSTALL=true

# homebrew paths
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
# Put the brew cache under the brew prefix instead of ${HOME}/.cache/Homebrew
# so the installer's non-sudo `mkdir -p ${HOMEBREW_CACHE}` always lands in a
# directory we own, regardless of /home/${WORKSPACE_USER} permissions.
ENV HOMEBREW_CACHE=/home/linuxbrew/.cache/Homebrew
ENV HOMEBREW_NO_ANALYTICS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV HOMEBREW_NO_INSTALL_CLEANUP=1

###########################################################################
# Base System Tools
###########################################################################

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    bison \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    file \
    git \
    gosu \
    gnupg \
    less \
    locales \
    make \
    mercurial \
    openssl \
    patch \
    pkg-config \
    procps \
    rsync \
    screen \
    socat \
    sudo \
    tar \
    unzip \
    vim \
    wget \
    xz-utils \
    zip \
    zsh \
    zsh-syntax-highlighting \
    && if [ "${WORKSPACE_INSTALL_DNSUTILS}" = "true" ]; then \
    apt-get install -y --no-install-recommends dnsutils iputils-ping net-tools; \
    fi \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && groupadd -g ${PGID} ${WORKSPACE_USER} \
    && useradd -m -u ${PUID} -g ${PGID} -s /bin/zsh ${WORKSPACE_USER} \
    && echo "${WORKSPACE_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${WORKSPACE_USER} \
    && chmod 0440 /etc/sudoers.d/${WORKSPACE_USER}

###########################################################################
# mise - Universal Language Version Manager
###########################################################################

RUN mkdir -p ${MISE_DATA_DIR} ${MISE_CONFIG_DIR} ${MISE_CACHE_DIR} ${WORKSPACE_PATH} \
    && curl https://mise.run | sh \
    && mv /root/.local/bin/mise /usr/local/bin/mise \
    && chmod +x /usr/local/bin/mise \
    && mise trust -a \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${MISE_DATA_DIR} ${MISE_CONFIG_DIR} ${MISE_CACHE_DIR} ${WORKSPACE_PATH}

###########################################################################
# Pre-install languages via mise at build time (optional)
###########################################################################

RUN if [ -n "${WORKSPACE_PREINSTALL_LANGUAGES}" ]; then \
    su - ${WORKSPACE_USER} -c "export PATH=\"/usr/local/bin:\${PATH}\" && mise install ${WORKSPACE_PREINSTALL_LANGUAGES}" \
    && su - ${WORKSPACE_USER} -c "export PATH=\"/usr/local/bin:\${PATH}\" && mise reshim"; \
    fi

###########################################################################
# homebrew
###########################################################################

RUN if [ "${WORKSPACE_INSTALL_BREW}" = "true" ]; then \
    mkdir -p /home/linuxbrew ${HOMEBREW_CACHE} \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} /home/linuxbrew \
    # Defensive: in some build environments (Docker Desktop on macOS in
    # particular) /home/${WORKSPACE_USER} ends up not writable by
    # ${WORKSPACE_USER} after useradd -m, which then breaks any
    # `su - ${WORKSPACE_USER} -c '... ~/.cache/...'` operation. Force the
    # ownership and mode that useradd -m should have produced.
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} /home/${WORKSPACE_USER} \
    && chmod 755 /home/${WORKSPACE_USER} \
    && su - ${WORKSPACE_USER} -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
    && su - ${WORKSPACE_USER} -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew update --quiet' \
    && if [ -n "${WORKSPACE_BREW_PACKAGES}" ]; then \
    su - ${WORKSPACE_USER} -c "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\" && brew install ${WORKSPACE_BREW_PACKAGES}"; \
    fi; \
    fi

###########################################################################
# zsh + oh-my-zsh configuration
###########################################################################

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" -- \
    --unattended --keep-zshrc \
    && cp -R /root/.oh-my-zsh ${WORKSPACE_HOME}/.oh-my-zsh \
    && printf '%s\n' \
    'export ZSH="$HOME/.oh-my-zsh"' \
    'ZSH_THEME="robbyrussell"' \
    'plugins=(git)' \
    '' \
    '# mise activation' \
    'eval "$(/usr/local/bin/mise activate zsh)"' \
    '' \
    '# auto-detect project stack on cd — generates .mise.toml from' \
    '# package.json / go.mod / Cargo.toml / composer.json / pyproject.toml' \
    '# and lets MISE_AUTO_INSTALL=true do the rest. Set MISED_SKIP_DETECT=1' \
    '# to silence this hook (e.g. for a project that intentionally has no config).' \
    'detect_stack_on_cd() {' \
    '  [ -n "${MISED_SKIP_DETECT:-}" ] && return' \
    '  [ -f .mise.toml ] || [ -f .tool-versions ] && return' \
    '  command -v detect-stack >/dev/null 2>&1 || return' \
    '  detect-stack . >/dev/null 2>&1' \
    '}' \
    'chpwd_functions+=(detect_stack_on_cd)' \
    '' \
    '# homebrew shellenv' \
    'if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; fi' \
    'source "$ZSH/oh-my-zsh.sh"' \
    'source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
    > ${WORKSPACE_HOME}/.zshrc \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${WORKSPACE_HOME}/.oh-my-zsh ${WORKSPACE_HOME}/.zshrc

###########################################################################
# SSH (optional)
###########################################################################

RUN if [ "${WORKSPACE_INSTALL_WORKSPACE_SSH}" = "true" ]; then \
    apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && mkdir -p /run/sshd ${WORKSPACE_HOME}/.ssh \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${WORKSPACE_HOME}/.ssh \
    && chmod 700 ${WORKSPACE_HOME}/.ssh; \
    fi

###########################################################################
# Final Touch & Entrypoint
###########################################################################

COPY --chmod=755 workspaces/docker-entrypoint.sh        /usr/local/bin/workspace-entrypoint
COPY --chmod=755 workspaces/scripts/detect-stack.sh    /usr/local/bin/detect-stack
COPY --chmod=755 workspaces/scripts/init-project.sh    /usr/local/bin/init-project

RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm -f /var/log/lastlog /var/log/faillog \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${WORKSPACE_HOME}

WORKDIR ${WORKSPACE_PATH}

ENTRYPOINT ["workspace-entrypoint"]
CMD ["sleep", "infinity"]
