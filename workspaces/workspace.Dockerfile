#--------------------------------------------------------------------------
# Development Workspace
#--------------------------------------------------------------------------
# 职责：提供 100% 通用的开发"壳"，不含任何语言运行时
# 语言运行时通过 mise 在构建时或启动时按需安装
#--------------------------------------------------------------------------

ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE}

# BuildKit provides TARGETARCH for the requested target platform.
ARG TARGETARCH

LABEL maintainer="muxk <361087696@qq.com>"
LABEL description="Development workspace with mise, homebrew, zsh"

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
ARG TARGETARCH

ARG WORKSPACE_INSTALL_DNSUTILS=false
ARG WORKSPACE_INSTALL_WORKSPACE_SSH=false
ARG WORKSPACE_INSTALL_BREW=true
ARG WORKSPACE_BREW_PACKAGES="jq yq ripgrep fzf tree tmux fd neovim"

# mise pre-installed languages at build time (e.g. "go@1.22.4 rust@stable php@8.3.6")
ARG WORKSPACE_PREINSTALL_LANGUAGES=""
# Pin mise to a specific release. Override through the Compose build arg.
ARG MISE_VERSION=v2026.6.1
ARG MISE_RELEASE_BASE_URL=https://github.com/jdx/mise/releases/download

# Proxy support: declared as ARG, exported as ENV (both upper- and lower-case so
# apt, curl, go, and pip all pick it up). Leave HTTP_PROXY empty in .env to
# disable. The compose file passes these as build args.
ARG HTTP_PROXY=
ARG HTTPS_PROXY=
ARG NO_PROXY=localhost,127.0.0.1,::1,.local
ARG DEBIAN_MIRROR=deb.debian.org
ARG DEBIAN_SECURITY_MIRROR=security.debian.org

ENV TZ=${TZ}
ENV WORKSPACE_USER=${WORKSPACE_USER}
ENV WORKSPACE_HOME=${WORKSPACE_HOME}
ENV WORKSPACE_PATH=${WORKSPACE_PATH}
# Pin $SHELL so any process reading it (mise, oh-my-zsh, IDEs that fall
# back to the env var) sees /bin/zsh. Pairs with useradd -s /bin/zsh above
# and the host-side VSCode setting terminal.integrated.defaultProfile.linux.
ENV SHELL=/bin/zsh
# locale-gen above creates en_US.UTF-8; export it so Python / git / locale-
# aware tools don't fall back to POSIX (which breaks `print('中文')` and
# similar). LC_ALL is also exported so gettext-style tools pick the same
# locale without per-tool override.
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

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
# Keep mise shims available to non-interactive shells as well. Interactive
# zsh still evaluates `mise activate zsh` for project-aware environment setup.
ENV PATH=${MISE_DATA_DIR}/shims:/usr/local/bin:${PATH}
# Project detection is explicit by default. Set WORKSPACE_AUTO_DETECT=true to
# opt into generating .mise.toml on directory changes.
ENV MISE_AUTO_INSTALL=false
ENV WORKSPACE_AUTO_DETECT=false

# homebrew paths
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
# Put the brew cache under the brew prefix instead of ${HOME}/.cache/Homebrew
# so the installer's non-sudo `mkdir -p ${HOMEBREW_CACHE}` always lands in a
# directory we own, regardless of /home/${WORKSPACE_USER} permissions.
ENV HOMEBREW_CACHE=/home/linuxbrew/.cache/Homebrew
ENV HOMEBREW_NO_ANALYTICS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV HOMEBREW_NO_INSTALL_CLEANUP=1
# Keep brew usable from VS Code tasks, bash, and non-login shells too. The
# zshrc still runs `brew shellenv` for the remaining Homebrew environment.
ENV PATH=${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${MISE_DATA_DIR}/shims:/usr/local/bin:${PATH}

###########################################################################
# Base System Tools
###########################################################################

# Retry wrapper: apt-get returns exit code 100 when "Some files failed to
# download" — a transient network blip against Debian mirrors shouldn't fail
# the whole image build. Both package-list updates and package installs retry.
# Bootstrap over HTTP so ca-certificates can be installed before HTTPS
# verification is enabled. All subsequent apt traffic uses HTTPS.
RUN set -eux; \
    find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec \
      sed -i -E \
        -e "s#https?://deb.debian.org#http://${DEBIAN_MIRROR}#g" \
        -e "s#https?://security.debian.org#http://${DEBIAN_SECURITY_MIRROR}#g" \
      {} +; \
    apt_update() { \
      for attempt in 1 2 3; do \
        if apt-get update -o Acquire::Retries=5; then \
          return 0; \
        fi; \
        echo "apt update failed (attempt ${attempt}/3); clearing apt lists" >&2; \
        rm -rf /var/lib/apt/lists/*; \
        sleep 3; \
      done; \
      echo "apt update failed after 3 attempts" >&2; \
      return 1; \
    }; \
    apt_install() { \
      for attempt in 1 2 3; do \
        if apt-get install -y --no-install-recommends --fix-missing \
          -o Acquire::Retries=5 "$@"; then \
          return 0; \
        fi; \
        echo "apt install failed (attempt ${attempt}/3); refreshing package lists" >&2; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*; \
        apt_update; \
      done; \
      echo "apt install failed after 3 attempts: $*" >&2; \
      return 1; \
    }; \
    rm -rf /var/lib/apt/lists/*; \
    apt_update; \
    apt_install ca-certificates; \
    find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec \
      sed -i \
        -e "s#http://${DEBIAN_MIRROR}#https://${DEBIAN_MIRROR}#g" \
        -e "s#http://${DEBIAN_SECURITY_MIRROR}#https://${DEBIAN_SECURITY_MIRROR}#g" \
      {} +; \
    rm -rf /var/lib/apt/lists/*; \
    apt_update; \
    apt_install \
      bash \
      binutils \
      bison \
      build-essential \
      bzip2 \
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
      zsh-syntax-highlighting; \
    if [ "${WORKSPACE_INSTALL_DNSUTILS}" = "true" ]; then \
      apt_install dnsutils iputils-ping net-tools; \
    fi; \
    if [ "${WORKSPACE_INSTALL_WORKSPACE_SSH}" = "true" ]; then \
      apt_install openssh-server; \
    fi; \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
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

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) MISE_ARCH="x64" ;; \
      arm64) MISE_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETARCH for mise: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    MISE_URL="${MISE_RELEASE_BASE_URL}/${MISE_VERSION}/mise-${MISE_VERSION}-linux-${MISE_ARCH}"; \
    mkdir -p ${MISE_DATA_DIR} ${MISE_CONFIG_DIR} ${MISE_CACHE_DIR} ${WORKSPACE_PATH}; \
    echo "Downloading mise ${MISE_VERSION} for linux-${MISE_ARCH}"; \
    curl --fail --location --show-error --retry 5 --retry-all-errors --retry-delay 3 \
      "${MISE_URL}" -o /usr/local/bin/mise; \
    chmod +x /usr/local/bin/mise; \
    /usr/local/bin/mise --version; \
    chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${MISE_DATA_DIR} ${MISE_CONFIG_DIR} ${MISE_CACHE_DIR} ${WORKSPACE_PATH}

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
    echo "[workspace] Homebrew: preparing directories"; \
    mkdir -p /home/linuxbrew ${HOMEBREW_CACHE} \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} /home/linuxbrew \
    # Defensive: in some build environments (Docker Desktop on macOS in
    # particular) /home/${WORKSPACE_USER} ends up not writable by
    # ${WORKSPACE_USER} after useradd -m, which then breaks any
    # `su - ${WORKSPACE_USER} -c '... ~/.cache/...'` operation. Force the
    # ownership and mode that useradd -m should have produced.
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} /home/${WORKSPACE_USER} \
    && chmod 755 /home/${WORKSPACE_USER} \
    && echo "[workspace] Homebrew: configuring Git for unstable proxy links" \
    && su - ${WORKSPACE_USER} -c 'git config --global http.version HTTP/1.1; git config --global http.maxRequests 1; git config --global http.lowSpeedLimit 1; git config --global http.lowSpeedTime 600' \
    && echo "[workspace] Homebrew: downloading installer" \
    && su - ${WORKSPACE_USER} -c 'set -e; curl --fail --location --show-error --retry 5 --retry-all-errors --retry-delay 3 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o /tmp/homebrew-install.sh; for attempt in 1 2 3; do if NONINTERACTIVE=1 CI=1 /bin/bash /tmp/homebrew-install.sh; then rm -f /tmp/homebrew-install.sh; exit 0; fi; echo "Homebrew installer failed (attempt ${attempt}/3); retrying" >&2; sleep $((attempt * 5)); done; rm -f /tmp/homebrew-install.sh; exit 1' \
    && echo "[workspace] Homebrew: updating metadata" \
    && su - ${WORKSPACE_USER} -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && HOMEBREW_VERBOSE=1 brew update' \
    && if [ -n "${WORKSPACE_BREW_PACKAGES}" ]; then \
    echo "[workspace] Homebrew: installing ${WORKSPACE_BREW_PACKAGES}"; \
    su - ${WORKSPACE_USER} -c "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\" && HOMEBREW_VERBOSE=1 brew install --verbose ${WORKSPACE_BREW_PACKAGES}"; \
    echo "[workspace] Homebrew: packages installed"; \
    fi; \
    fi

###########################################################################
# zsh + oh-my-zsh configuration
###########################################################################

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" -- \
    --unattended --keep-zshrc \
    && cp -R /root/.oh-my-zsh ${WORKSPACE_HOME}/.oh-my-zsh \
    && chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${WORKSPACE_HOME}/.oh-my-zsh

# Source-controlled zsh config. Edited like any other file — diff lives in
# git, no need to rebuild the image to tweak. Same content as the previous
# inline printf; preserved verbatim so `cd` autocompletion, brew shellenv,
# and detect_stack_on_cd keep working.
COPY --chown=${WORKSPACE_USER}:${WORKSPACE_USER} --chmod=644 \
    workspaces/dotfiles/.zshrc ${WORKSPACE_HOME}/.zshrc

###########################################################################
# SSH (optional install handled by the apt block above; /run/sshd and
# ${WORKSPACE_HOME}/.ssh are recreated by docker-entrypoint.sh at runtime
# because /run is tmpfs in Debian and the build-time directory is gone on
# the first container start).
###########################################################################

###########################################################################
# Final Touch & Entrypoint
###########################################################################

COPY --chmod=755 workspaces/docker-entrypoint.sh        /usr/local/bin/workspace-entrypoint
COPY --chmod=755 workspaces/scripts/detect-stack.sh    /usr/local/bin/detect-stack
COPY --chmod=755 workspaces/scripts/init-project.sh    /usr/local/bin/init-project
COPY --chmod=644 workspaces/scripts/languages.defaults /usr/local/bin/languages.defaults
COPY --chmod=644 workspaces/scripts/stack-detection.lib.sh /usr/local/bin/stack-detection.lib.sh

RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm -f /var/log/lastlog /var/log/faillog

WORKDIR ${WORKSPACE_PATH}

ENTRYPOINT ["workspace-entrypoint"]
CMD ["sleep", "infinity"]
