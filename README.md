# development-docker

基于 Docker Compose 的可定制开发环境。默认只启动 `workspace`，代码从宿主机 `~/codes` 挂载到容器 `/workspace`，容器内开发用户为 `developer`。

## Quick Start

```bash
cp .env.example .env
mkdir -p ~/codes
docker compose up -d workspace
docker compose exec workspace zsh
```

## Profiles

按需启用基础设施，避免每次启动完整服务栈。每个服务都声明了 `profiles:`，可以使用 `docker compose --profile <name> up -d` 精确拉起子集。

```bash
# 数据库（mysql / postgres / mongo / postgis 可单独指定）
docker compose --profile mysql up -d
docker compose --profile postgres up -d
docker compose --profile mongo up -d
docker compose --profile gis up -d

# 缓存
docker compose --profile cache up -d    # = redis

# 消息队列
docker compose --profile mq up -d       # = kafka + kafka-ui

# 对象存储
docker compose --profile storage up -d  # = minio

# 注册/协调服务
docker compose --profile registry up -d  # = etcd + etcd-manager + dtm

# 可观测性
docker compose --profile observability up -d   # = es + logstash + kibana + grafana + prometheus + jaeger

# CI / 管理工具
docker compose --profile ci up -d       # = gitlab + gitlab-runner + portainer

# 网关
docker compose --profile gateway up -d  # = traefik

# API 文档工具
docker compose --profile docs up -d     # = swagger-editor + swagger-ui

# 多个 profile 同时拉起
docker compose --profile mysql --profile redis --profile kafka up -d
```

### 预设组合 (Presets)

预设由 Makefile 提供，对应常用语言栈：

```bash
make go-env     # workspace + mysql + redis + etcd + dtm
make rust-env   # workspace + postgres + redis
make php-env    # workspace + mysql + redis
make full-env   # 全部服务（资源消耗大，慎用）
```

## Workspace

### 语言版本管理

workspace 使用 [mise](https://mise.jdx.dev/) 管理语言版本。零配置流程：

1. 容器已开启 `MISE_AUTO_INSTALL=true`——进入含 `.mise.toml` 的目录时，缺失的 toolchain 会按需安装
2. zsh 配置了 `chpwd` 钩子，首次 `cd` 进项目目录时自动调用 `detect-stack` 扫描 `package.json` / `go.mod` / `Cargo.toml` / `composer.json` / `pyproject.toml`，**生成 `.mise.toml`**（已存在则跳过）
3. 生成完成后直接 `mise use go@1.x` 或运行命令即可，工具链按需落地

**自动嗅探规则：**

| 项目文件 | 嗅探到的 tool + 默认版本 |
|---|---|
| `package.json` | `node` (engines.node 优先，否则 `22`) |
| `go.mod` | `go` (取 `go` 指令，否则 `1.23`) |
| `Cargo.toml` | `rust` (rust-version 优先，否则 `stable`) |
| `composer.json` | `php` (require.php 优先，否则 `8.3`) |
| `pyproject.toml` / `requirements.txt` | `python` (requires-python 优先，否则 `3.12`) |

**交互式初始化（自动嗅探 + 确认/覆盖/追加）：**

```bash
# 在容器内，针对某个项目目录
docker compose exec workspace zsh
cd ~/codes/my-project
init-project                 # 交互式生成 .mise.toml
```

**手动管理（覆盖自动嗅探）：**

```bash
# 安装并锁定到当前项目
mise use go@1.22.4
mise use node@22

# 设置全局默认（影响所有无项目级配置的项目）
mise use -g go@1.22.4

# 查看已安装版本
mise ls
```

**跳过自动嗅探（按项目关闭）：**

```bash
export MISED_SKIP_DETECT=1    # 之后再 cd 就不再生成 .mise.toml
```

> `detect-stack` 是静默的——没有可识别的项目文件时直接退出；`init-project` 总是交互式。两者都不会覆盖已存在的 `.mise.toml` / `.tool-versions`。

### Workspace 构建

`workspace` 通过 `.env` 中的 build args 控制基础工具链：

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

- mise 数据和缓存: `/home/developer/.local/share/mise` 和 `/home/developer/.cache/mise`
- Go 模块: `/home/developer/go/pkg/mod`
- Cargo registry 和 git: `/home/developer/.cargo/registry` 和 `/home/developer/.cargo/git`
- Composer: `/home/developer/.composer`
- Homebrew cache: `/home/developer/.cache/Homebrew`

## SSH

workspace 支持安装 SSH 服务，但私钥不再写入镜像。需要 SSH 登录时，建议把宿主机公钥写入容器内：

```bash
docker compose exec workspace zsh
mkdir -p ~/.ssh
vim ~/.ssh/authorized_keys
```

也可以按项目需要增加运行时只读挂载，例如将宿主机 `authorized_keys` 挂载到 `/home/developer/.ssh/authorized_keys`。

## Validate

```bash
docker compose config
docker compose --profile db --profile cache --profile mq config
```

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
