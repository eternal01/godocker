# development-docker

基于 Docker Compose 的可迁移、多语言开发环境。宿主机 `~/codes` 映射到容器 `/workspace`，workspace 内使用 `developer` 作为开发用户。

项目提供一个包含 SSH 服务的 workspace 容器，并按需提供数据库、缓存、消息队列、注册中心、监控、CI 和网关等基础设施服务。开发工具链留在容器内，宿主机只需要 Docker、IDE 和 AI 应用。

## 快速开始

```bash
cp .env.example .env
mkdir -p ~/codes
docker compose build workspace
docker compose up -d workspace
```

进入开发终端：

```bash
docker compose exec -u developer workspace zsh
```

或使用项目命令桥：

```bash
./scripts/dev up
./scripts/dev shell
./scripts/dev exec go version
```

查看状态和日志：

```bash
docker compose ps
docker compose logs -f workspace
```

## 项目结构

```text
docker-compose.yml              workspace、网络和缓存卷
compose/                        可选基础设施 Compose 模块
workspaces/workspace.Dockerfile workspace 镜像
workspaces/docker-entrypoint.sh 容器入口和 SSHD 启动
workspaces/dotfiles/             shell 配置
workspaces/scripts/              语言探测和项目初始化
scripts/dev                      日常容器命令桥
scripts/dev-up.sh                语言环境预设启动
scripts/build-workspace.sh       workspace 多架构构建
```

## 用户与 SSH

workspace 容器以 root 启动入口，用于初始化权限和 SSHD；主开发进程和 SSH 登录会自动使用 `developer` 用户。

SSH 默认监听宿主机 `2222` 端口：

```bash
ssh developer@localhost -p 2222
```

公钥放入容器：

```bash
docker compose exec -u root workspace mkdir -p /home/developer/.ssh
docker compose exec -u root workspace sh -c \
  'cat >> /home/developer/.ssh/authorized_keys' < ~/.ssh/id_ed25519.pub
docker compose exec -u root workspace sh -c \
  'chown -R developer:developer /home/developer/.ssh && chmod 700 /home/developer/.ssh && chmod 600 /home/developer/.ssh/authorized_keys'
```

关闭 SSH：

```env
WORKSPACE_SSH_ENABLED=false
```

修改后重建容器：

```bash
docker compose up -d --force-recreate workspace
```

容器管理命令使用 root：

```bash
docker compose exec -u root workspace bash
```

日常开发命令使用 developer：

```bash
docker compose exec -u developer workspace zsh
```

## IDE 和 AI 工具

项目不依赖某个特定 IDE。所有 IDE 都可以通过 SSH、Docker Compose 或容器终端使用同一套环境。

推荐连接参数：

```text
Host: localhost
Port: 2222
User: developer
Workspace: /workspace
```

VS Code 用户可以使用项目内的 `.devcontainer/devcontainer.json` 重新打开容器；也可以直接使用 SSH。JetBrains、Cursor、Windsurf 等工具可以使用 SSH 远程开发或 Docker 解释器。

宿主机 GUI AI 应用直接打开 `~/codes/project`。项目命令通过容器执行：

```bash
./scripts/dev exec go test ./...
./scripts/dev exec cargo test
./scripts/dev exec composer install
./scripts/dev exec npm test
```

这样代码由宿主机编辑，SDK、编译器和依赖由 workspace 提供。

## 多语言环境

语言版本由 mise 管理：

```bash
docker compose exec -u developer workspace zsh
cd /workspace/my-project
init-project
mise install
mise ls
```

支持自动识别：

| 项目文件 | 工具 | 默认版本来源 |
|---|---|---|
| `package.json` | Node.js | `engines.node` 或 `22` |
| `go.mod` | Go | `go` 指令或 `1.23` |
| `Cargo.toml` | Rust | `rust-version` 或 `stable` |
| `composer.json` | PHP | `require.php` 或 `8.3` |
| `pyproject.toml` | Python | `requires-python` 或 `3.12` |
| `requirements.txt` | Python | `3.12` |

手动指定版本：

```bash
mise use go@1.23
mise use rust@stable
mise use php@8.3
mise install
```

镜像构建阶段预装语言：

```env
WORKSPACE_PREINSTALL_LANGUAGES="go@1.23 rust@stable php@8.3 node@22 python@3.12"
```

## Homebrew

系统底层软件通过 Debian 安装，通用 CLI 工具通过 Homebrew 安装，语言运行时通过 mise 管理。

修改默认工具：

```env
WORKSPACE_BREW_PACKAGES="jq yq ripgrep fzf tree tmux fd neovim"
```

重新构建：

```bash
docker compose build workspace
docker compose up -d workspace
```

容器内安装临时工具：

```bash
docker compose exec -u developer workspace brew install httpie
```

需要长期复现的工具应加入 `WORKSPACE_BREW_PACKAGES` 后重新构建镜像。

## 宿主机代理

在 `.env` 设置宿主机代理：

```env
HOST_PROXY_URL=http://host.docker.internal:7897
HTTP_PROXY=${HOST_PROXY_URL}
HTTPS_PROXY=${HOST_PROXY_URL}
```

代理会用于镜像构建和容器运行阶段的 apt、mise、Homebrew、Go、Rust、PHP 等下载。

如果代理只监听宿主机回环地址：

```env
HOST_PROXY_URL=http://127.0.0.1:7897
WORKSPACE_BUILD_NETWORK=host
```

没有代理时将 `HOST_PROXY_URL` 留空。

## Debian 软件源

默认使用官方源：

```env
DEBIAN_MIRROR=deb.debian.org
DEBIAN_SECURITY_MIRROR=security.debian.org
```

也可以切换镜像：

```env
DEBIAN_MIRROR=mirrors.aliyun.com
DEBIAN_SECURITY_MIRROR=mirrors.aliyun.com
```

构建日志：

```bash
docker compose --progress=plain build workspace
```

## 多架构构建

普通 Compose 构建当前 Docker 主机架构：

```bash
docker compose build workspace
```

构建单一指定架构并加载到本地：

```bash
PLATFORMS=linux/arm64 make build-workspace-multiarch
```

构建并推送 amd64/arm64 多架构镜像：

```bash
docker buildx create --name development-docker-builder --use
docker buildx inspect --bootstrap
PUSH=1 WORKSPACE_IMAGE=registry.example.com/team/workspace:latest \
  PLATFORMS=linux/amd64,linux/arm64 make build-workspace-multiarch
```

多架构构建必须推送到镜像仓库，不能通过普通 `--load` 加载 manifest list。

## 基础设施服务

默认只启动 workspace。可按需使用 Compose profile：

```bash
docker compose --profile mysql up -d
docker compose --profile postgres up -d
docker compose --profile cache up -d
docker compose --profile mq up -d
docker compose --profile registry up -d
docker compose --profile storage up -d
docker compose --profile observability up -d
docker compose --profile ci up -d
docker compose --profile gateway up -d
docker compose --profile docs up -d
```

语言预设：

```bash
make go-env
make rust-env
make php-env
```

完整环境：

```bash
make full-env
```

完整环境资源消耗较大。也可以指定服务：

```bash
make dev workspace mysql redis
```

## 镜像检查与缓存

普通启动使用 Docker 本地缓存。需要检查所有 profile 镜像时：

```bash
make check
```

需要启动前执行镜像检查：

```bash
CHECK_VERSIONS=1 make go-env
```

需要显式重新拉取镜像：

```bash
PULL_IMAGES=1 make go-env
```

更新 Compose 镜像和构建参数记录：

```bash
make lock
```

## 常用命令

```bash
make init
make build-workspace
make up
make shell
make ps
make logs
make down
make config
```

配置验证：

```bash
docker compose config
docker compose --profile mysql --profile cache config
```

## 持久化目录

宿主机代码目录：

```text
~/codes -> /workspace
```

常用 Docker volume：

```text
workspace-mise-cache
workspace-brew-cache
workspace-go-mod
workspace-cargo-registry
workspace-cargo-git
workspace-composer
```

基础设施数据默认位于：

```text
~/.development-docker/data
```

## 安全说明

`.env` 只用于本机配置，不应提交到 Git。示例文件中的数据库密码仅适合本地开发，请勿用于生产环境。

GitLab Runner 使用 Docker Socket 或 shell executor 时可能获得宿主机级权限，只应在可信环境中启用。
