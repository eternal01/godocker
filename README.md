# development-docker

基于 Docker Compose 的可迁移开发环境。宿主机 `~/codes` 映射到容器 `/workspace`，容器内开发用户为 `developer`。默认只启动开发容器，数据库、缓存和中间件按需启用。

## 快速开始

```bash
cp .env.example .env
mkdir -p ~/codes
docker compose up -d
docker compose exec workspace zsh
```

首次修改 `.env` 后，建议重新构建 workspace：

```bash
docker compose build workspace
docker compose up -d workspace
```

## 服务组合

`.env` 已通过 `COMPOSE_FILE` 加载全部 Compose 模块；默认仍只启动 `workspace`。使用 profile 按需启动基础设施：

```bash
docker compose --profile mysql up -d          # MySQL
docker compose --profile postgres up -d       # PostgreSQL
docker compose --profile gis up -d            # PostGIS
docker compose --profile cache up -d          # Redis
docker compose --profile mq up -d             # Kafka + Kafka UI
docker compose --profile storage up -d        # MinIO
docker compose --profile registry up -d       # etcd + DTM
docker compose --profile observability up -d  # ES / Kibana / Grafana 等
docker compose --profile ci up -d             # GitLab / Runner / Portainer
docker compose --profile gateway up -d        # Traefik
docker compose --profile docs up -d           # Swagger Editor / UI
```

常用预设：

```bash
make go-env       # workspace + MySQL + Redis + etcd + DTM
make rust-env     # workspace + PostgreSQL + Redis
make php-env      # workspace + MySQL + Redis
make full-env     # 完整环境，资源消耗较大
```

停止并清理容器：

```bash
make down
```

## Workspace

### 语言版本管理

workspace 使用 [mise](https://mise.jdx.dev/) 管理语言版本。**默认手动维护**——切换项目时不会触发自动 install，避免在 Go / Rust 项目之间快速横跳时下载意料外的 toolchain；迁移 / 全新 bootstrap 时可一键切换到自动模式。

#### 日常流程（默认，显式初始化）

默认不会因为 `cd` 进入项目而修改文件。使用 `init-project` 显式扫描并生成 `.mise.toml`，再手动执行 `mise install`。

```bash
docker compose exec workspace zsh
cd /workspace/my-project
init-project                # 显式生成 .mise.toml
mise install                # 手动 install 当前项目 toolchain
```

之后进出该项目不会触发探测或安装。

#### 迁移 / 全新 bootstrap 场景（可选自动模式）

```bash
docker compose exec workspace zsh
export WORKSPACE_AUTO_DETECT=true
export MISE_AUTO_INSTALL=true
cd /workspace/legacy-app       # opt-in 后才会生成配置并安装
unset WORKSPACE_AUTO_DETECT MISE_AUTO_INSTALL
```

自动模式只建议用于迁移或全新环境初始化。

> 为什么不用默认 `MISE_AUTO_INSTALL=true`：在 Go 项目里临时 `cd` 进 Rust 工程看一眼，会自动下载 stable toolchain + 几百 MB 缓存；切回去再 `cd` Rust 又来一次。手动 install 一次之后工具链在 volume 里复用，切换成本几乎为零。

#### 嗅探规则

| 项目文件 | 嗅探到的 tool + 默认版本 |
|---|---|
| `package.json` | `node`（`engines.node` 优先，否则 `22`） |
| `go.mod` | `go`（取 `go` 指令，否则 `1.23`） |
| `Cargo.toml` | `rust`（`rust-version` 优先，否则 `stable`） |
| `composer.json` | `php`（`require.php` 优先，否则 `8.3`） |
| `pyproject.toml` / `requirements.txt` | `python`（`requires-python` 优先，否则 `3.12`） |

#### 交互式初始化（嗅探 + 确认/覆盖/追加）

```bash
docker compose exec workspace zsh
cd /workspace/my-project
init-project              # 交互式生成 .mise.toml
```

`detect-stack` 是静默的，`init-project` 总是交互式。两者都**不覆盖**已存在的 `.mise.toml` / `.tool-versions`。

#### 手动管理（覆盖嗅探结果）

```bash
mise use go@1.22.4        # 安装并锁定到当前项目
mise use node@22

mise use -g go@1.22.4     # 全局默认（影响所有无项目级配置的项目）

mise ls                   # 查看已安装版本
```

### 镜像内预装语言

如需在构建阶段预装多个工具链，可在 `.env` 设置：

```dotenv
WORKSPACE_PREINSTALL_LANGUAGES="go@1.23 rust@stable php@8.3 node@22 python@3.12"
```

然后重新构建 workspace。版本安装由 `mise` 管理，运行时会复用镜像内工具链和持久化缓存。

### Homebrew

除 Debian 基础包外的通用命令行工具优先通过 Homebrew 安装。修改 `WORKSPACE_BREW_PACKAGES` 后重新构建：

```dotenv
WORKSPACE_BREW_PACKAGES="jq ripgrep fd bat"
```

Homebrew 下载缓存会持久化，但 Homebrew 安装目录保留在镜像层中，不会被空 volume 覆盖。

### 使用主机代理

如果宿主机运行 Clash、Surge、mitmproxy 等 HTTP 代理，在 `.env` 中设置代理地址：

```dotenv
HOST_PROXY_URL=http://host.docker.internal:7897
```

该配置同时用于镜像构建和容器运行，可加速 Debian、mise、Homebrew、Go、Rust、PHP 等依赖下载。修改后重新构建：

```bash
docker compose build workspace
docker compose up -d workspace
```

如果代理只监听宿主机 `127.0.0.1`，改用：

```dotenv
HOST_PROXY_URL=http://127.0.0.1:7897
WORKSPACE_BUILD_NETWORK=host
```

此模式依赖 Docker 引擎支持 host build network；优先使用 `host.docker.internal`，可获得更好的跨平台兼容性。

#### 跳过嗅探（自动模式下使用）

```bash
export MISED_SKIP_DETECT=1    # 之后再 cd 就不再生成 .mise.toml
```

### Workspace 构建

`workspace` 通过 `.env` 中的 build args 控制基础工具链。构建时预装的 mise 工具和 Homebrew prefix 保留在镜像中，Compose 只持久化缓存，不会用空 volume 覆盖它们：

```env
WORKSPACE_INSTALL_BREW=true
WORKSPACE_BREW_PACKAGES="jq yq ripgrep fzf tree tmux fd neovim"
```

通用开发工具通过 Homebrew 安装，进入容器后也可以直接使用：

```bash
brew search jq
brew install httpie
```

语言缓存使用 Docker volume 保存：

- mise 缓存: `/home/developer/.cache/mise`
- Go 模块: `/home/developer/go/pkg/mod`
- Cargo registry 和 git: `/home/developer/.cargo/registry` 和 `/home/developer/.cargo/git`
- Composer: `/home/developer/.composer`
- Homebrew cache: `/home/linuxbrew/.cache/Homebrew`

## SSH

workspace 支持安装 SSH 服务，但私钥不再写入镜像。需要 SSH 登录时，建议把宿主机公钥写入容器内：

```bash
docker compose exec workspace zsh
mkdir -p ~/.ssh
vim ~/.ssh/authorized_keys
```

也可以按项目需要增加运行时只读挂载，例如将宿主机 `authorized_keys` 挂载到 `/home/developer/.ssh/authorized_keys`。

## IDE Integration

容器内 `developer` 用户的登录 shell 已是 `/bin/zsh`，oh-my-zsh + 主题也已就位。但 VSCode 的集成终端 **不会读 `/etc/passwd`**——它有自己的配置，所以"开箱即用"还是 bash。要拿到 zsh 终端，按你的接入方式二选一：

### 方式 1：Reopen in Container（推荐）

项目自带 `.devcontainer/devcontainer.json`，会在「在容器中重新打开」时自动应用：

```bash
code /Users/mask/codes/development-docker
# VSCode 弹出提示 → "Reopen in Container"
# 或命令面板: Dev Containers: Reopen in Container
```

devcontainer.json 已配置 `terminal.integrated.defaultProfile.linux = zsh`，并自动安装 `hverlin.mise-vscode`（`.mise.toml` 语法高亮）。sh / bash 命令面板里同时保留两种 profile 可手动切换。

### 方式 2：Attach to Running Container

如果更喜欢手动 `docker compose up -d workspace` 后再附加：

1. 启动容器：`docker compose up -d workspace`
2. VSCode 命令面板 → **Dev Containers: Attach to Running Container** → 选 `development-docker-workspace`
3. 在**宿主机** VSCode 的 `settings.json`（`~/Library/Application Support/Code/User/settings.json` on macOS）加：

   ```json
   {
     "terminal.integrated.defaultProfile.linux": "zsh"
   }
   ```

   之后所有 Linux 远程终端默认就是 zsh。`devcontainer.json` 的 `settings` 块在「附加」模式下不会被应用，所以这是必经的一步。

### 验证

进容器后：

```bash
echo $SHELL          # /bin/zsh
echo $0              # -zsh   (表示当前 shell 是 zsh)
ps -p $$ -o comm=    # zsh
```

> 默认不会自动修改项目文件；需要自动模式时设置 `WORKSPACE_AUTO_DETECT=true`。

## 配置与验证

```bash
docker compose config
docker compose --profile mysql --profile cache --profile mq config
make lock
```

`.env.lock` 记录当前 Compose profile 解析出的镜像引用和构建参数。它能帮助复现配置，但镜像 tag 仍可能被远端覆盖；需要严格不可变构建时应进一步锁定 digest。

## Makefile 命令

```bash
make init             # 创建宿主机目录和基础配置
make build-workspace  # 构建 workspace 镜像
make ps               # 查看服务状态
make logs             # 查看日志
make check-versions   # 检查镜像版本
make lock             # 更新 .env.lock
```

## 目录说明

| 路径 | 用途 |
|---|---|
| `docker-compose.yml` | workspace、网络和持久化缓存 |
| `compose/` | 数据库、中间件和工具服务模块 |
| `workspaces/workspace.Dockerfile` | workspace 镜像定义 |
| `workspaces/` | 入口脚本、zsh 配置和语言探测工具 |
| `scripts/` | 启动、版本检查和锁定脚本 |
| `.env.example` | 配置模板 |
| `.env.lock` | Compose 镜像与构建参数锁定结果 |

## Traefik 路由（opt-in）

默认情况下，各服务直接通过宿主端口访问（`localhost:3306`、`localhost:6379` 等）。如需统一通过 Traefik 反向代理：

1. 编辑 `.env`，将 `TRAEFIK_ENABLE` 设为 `true`：
   ```env
   TRAEFIK_ENABLE=true
   TRAEFIK_DOMAIN=docker.localhost
   ```
2. 启动 Traefik + 目标服务：
   ```bash
   make gateway-routed PROFILES="mysql,redis,kafka-ui,grafana"
   # 或完整启动
   docker compose --profile gateway --profile mysql --profile redis up -d
   ```
3. 将 `*.${TRAEFIK_DOMAIN}` 加入 `/etc/hosts`：
   ```bash
   # 一键添加（macOS / Linux）
   for svc in mysql postgres redis minio kafka-ui grafana; do
     grep -q "$$svc.${TRAEFIK_DOMAIN}" /etc/hosts || \
       echo "127.0.0.1 $$svc.${TRAEFIK_DOMAIN}" | sudo tee -a /etc/hosts
   done
   ```
4. 访问 `http://mysql.docker.localhost:80`、`http://grafana.docker.localhost` 等

> 关闭路由：将 `TRAEFIK_ENABLE` 改回 `false`，重启服务即可。各服务的 `ports:` 仍然映射到宿主端口。

## ⚠️ 安全提示

### GitLab Runner

默认配置下 `gitlab-runner` 使用 `shell` executor 并挂载 `/var/run/docker.sock`，**等同于宿主机 root 权限**：

- 任何能在 CI 流水线中运行命令的人（恶意/被入侵的依赖）都能读写宿主机任意文件
- 挂载 docker.sock 后可以启动特权容器，实现容器逃逸
- 仅在可信的本地开发场景使用

如需更安全的方式：
- 改用 `dind`（Docker-in-Docker）sidecar，配置 `GITLAB_RUNNER_EXECUTOR=docker` 并配合 `DOCKER_HOST` 指向 dind
- 或将 `gitlab-runner` 服务拆到独立 VM/容器中

详见 [OPTIMIZATION_PLAN.md 2.3](./OPTIMIZATION_PLAN.md) 章节。

### 默认密码

`.env.example` 中的密码（`root/root`、`secret` 等）**仅用于本地开发**。生产或团队共享环境请用 `openssl rand -base64 24` 替换。
