# Service 灵活组合方案提案

## 当前痛点

目前通过 Makefile 的 preset（`go-env`、`rust-env` 等）或手动多文件组合启动服务：

- **Preset 硬编码**：`go-env` 固定包含 `db+cache+registry`，无法按需剔除不需要的数据库。
- **多文件组合粒度太粗**：`compose/db.yml` 同时拉起 MySQL + PostgreSQL + Mongo + PostGIS，多数场景只需要其中一种。
- **无法一键指定“仅 MySQL + Redis”**：用户必须记住一长串 `-f docker-compose.yml -f compose/db.yml -f compose/cache.yml`，且会拉起很多不需要的服务。

## 方案总览

引入三层灵活组合机制：

1. **服务级 Profile 标签**（最细粒度）
2. **动态 Compose 生成**（中等粒度）
3. **Makefile 交互式/声明式组合**（最粗粒度/用户体验层）

---

## 方案一（推荐）：服务级 Profiles + 动态生成

### 1. 为每个服务添加 `profiles`

修改 `compose/*.yml`，为每个服务打上多个标签：

```yaml
# compose/db.yml 示例
services:
  mysql:
    profiles: ["db", "mysql", "go-env", "php-env"]
    # ...
  postgres:
    profiles: ["db", "postgres", "rust-env"]
    # ...
  mongo:
    profiles: ["db", "mongo", "go-env"]
    # ...
  postgres-postgis:
    profiles: ["db", "gis", "postgis"]
    # ...
```

```yaml
# compose/cache.yml 示例
services:
  redis:
    profiles: ["cache", "redis", "go-env", "rust-env", "php-env"]
```

### 2. 引入服务级声明文件 `.env.services`

```bash
# .env.services（可由 make init 自动生成）
ENABLED_SERVICES="workspace mysql redis"
# 或简写：
PRESET=go-micro  # 内置预设名
```

### 3. Makefile 动态组合

```makefile
# Makefile 增加
COMPOSE_FILE ?= docker-compose.yml
ENABLED_SERVICES ?= workspace

# 动态解析服务到 profiles
# 用户输入：make up SERVICES="mysql redis etcd"
# 内部转换为：docker compose --profile mysql --profile redis --profile etcd up -d

up-custom: ## 启动指定服务：make up-custom SERVICES="mysql redis"
	@echo "Starting services: $(SERVICES)"
	$(eval PROFILES := $(foreach s,$(SERVICES),--profile $(s)))
	$(COMPOSE) $(PROFILES) up -d

# 提供预设别名
preset-go: ## Go 微服务开发环境
	@echo "Starting Go preset (workspace + mysql + redis + etcd + jaeger)"
	$(COMPOSE) --profile workspace --profile mysql --profile redis --profile etcd --profile jaeger up -d

preset-php: ## PHP 开发环境
	@echo "Starting PHP preset (workspace + mysql + redis + rabbitmq)"
	$(COMPOSE) --profile workspace --PROFILE mysql --profile redis --profile rabbitmq up -d
```

### 4. 优势

- **按需启动**：只启动真正需要的服务资源。
- **组合自由**：`make up-custom SERVICES="postgres redis minio"`
- **减少资源浪费**：不会同时启动 MySQL + PostgreSQL + MongoDB。
- **保持向后兼容**：原有 `docker compose -f compose/db.yml -f compose/cache.yml` 仍可用。

### 5. 实施要点

- 所有 `compose/*.yml` 中每个服务必须添加 `profiles`。
- `docker-compose.yml` 中的核心服务（workspace、网络、卷）保持**无 profiles**（默认启动）。
- README 中从 `--profile` 引导到多文件组合的示例需要同步更新为真正的 `--profile` 用法。
- 对于已有 `restart: always` 的服务，需确保未启用 profile 时不会被意外启动。

---

## 方案二：服务选择器脚本

如果暂时不想引入 profiles，可用一个 shell 脚本动态生成 compose 文件列表：

```bash
#!/bin/bash
# scripts/select-services.sh
# 用法: ./scripts/select-services.sh mysql redis etcd

COMPOSE_FILES=("docker-compose.yml")
for svc in "$@"; do
    case $svc in
        mysql|postgres|mongo|postgis) COMPOSE_FILES+=("compose/db.yml") ;;
        redis) COMPOSE_FILES+=("compose/cache.yml") ;;
        rabbitmq|kafka) COMPOSE_FILES+=("compose/mq.yml") ;;
        minio) COMPOSE_FILES+=("compose/storage.yml") ;;
        etcd|dtm) COMPOSE_FILES+=("compose/registry.yml") ;;
        elasticsearch|logstash|kibana|grafana|prometheus|jaeger) COMPOSE_FILES+=("compose/observability.yml") ;;
        gitlab|portainer) COMPOSE_FILES+=("compose/ci.yml") ;;
        traefik) COMPOSE_FILES+=("compose/gateway.yml") ;;
        swagger-editor|swagger-ui) COMPOSE_FILES+=("compose/docs.yml") ;;
    esac
done
# 去重并输出
printf "%s\n" "${COMPOSE_FILES[@]}" | sort -u
```

Makefile 中：

```makefile
up-custom:
	$(eval FILES := $(shell bash scripts/select-services.sh $(SERVICES)))
	$(COMPOSE) $(foreach f,$(FILES),-f $(f)) up -d
```

**缺点**：粒度仍受限于单个 compose 文件（db.yml 会同时拉起 4 个数据库），无法精确到单个服务。

---

## 方案三：引入 `COMPOSE_PROFILES` 环境变量 + 服务注册表

创建一个服务注册表 `services.yml`（或 JSON），描述每个服务的归属、依赖和默认 profile：

```yaml
services:
  mysql:
    file: compose/db.yml
    profiles: [db, mysql]
    depends_on: []
  postgres:
    file: compose/db.yml
    profiles: [db, postgres]
  redis:
    file: compose/cache.yml
    profiles: [cache, redis]
```

然后通过 Python/Node 脚本读取并生成正确的 `docker compose --profile ...` 命令。此方案可扩展性强，但引入额外运行时依赖。

---

## 推荐结论

短期采用 **方案一的 profiles 方式**（标准 Docker Compose 原生能力，无额外依赖），同时提供 **方案二脚本** 作为向下兼容的辅助工具：

1. 为所有 `compose/*.yml` 中的每个服务添加 `profiles` 字段。
2. 修改 Makefile，提供 `up-custom` 和 `preset-*` target。
3. 在 `.env` 或 `.env.services` 中支持 `ENABLED_SERVICES` 变量。
4. README Quick Start 中引导用户使用预设或自定义组合。

---

## 参考命令（实施后用户体验）

```bash
# 仅启动 workspace + MySQL + Redis（最常用）
make up-custom SERVICES="mysql redis"

# 启动 Go 开发全栈（预设）
make preset-go

# 手动使用原生 docker compose profile
export COMPOSE_PROFILES="mysql,redis,etcd"
docker compose up -d

# 查看当前所有可启动的服务列表
make list-services
```
