# DianZhan Bridge 部署

此部署只运行 Claude Code 与 Codex，并只开放 cc-connect Bridge WebSocket；不需要配置飞书、Telegram 或其他 IM 平台。

## 启动

```bash
cp deploy/bridge/.env.example deploy/bridge/.env
# 编辑 deploy/bridge/.env，填写两个模型 API Key、对应第三方 Base URL 和强随机 Bridge Token。
mkdir -p deploy/bridge/workspaces/dianzhan deploy/bridge/skills
```

`ANTHROPIC_BASE_URL` 必须是 Claude Code 所用的 Anthropic 兼容端点，
`OPENAI_BASE_URL` 必须是 Codex 所用的 OpenAI 兼容端点（通常以 `/v1` 结尾）。
配置会将 API Key 和 Base URL 分别绑定给 Claude Code 与 Codex。若上游指定模型名称，填入
`ANTHROPIC_MODEL` 或 `CODEX_MODEL`；Codex 上游若仅支持 Chat Completions，则将
`CODEX_WIRE_API` 从默认的 `responses` 改为 `chat`。

镜像由 GitHub Actions 构建并发布到 Docker Hub，服务器不执行 Docker build。首次启动和后续更新均使用：

```bash
docker compose --env-file deploy/bridge/.env -f docker-compose.bridge.yml pull
docker compose --env-file deploy/bridge/.env -f docker-compose.bridge.yml up -d
```

Linux 主机上，工作目录必须允许容器内 UID `10001` 写入：

```bash
sudo chown -R 10001:10001 deploy/bridge/workspaces/dianzhan
```

Bridge 默认只绑定 `127.0.0.1:9810`。需要由其他机器连接时，应在反向代理后暴露 WebSocket，并通过防火墙限制来源；不要直接将端口公开到互联网。

## 外部调用

先连接：

```text
ws://127.0.0.1:9810/bridge/ws?token=<CC_BRIDGE_TOKEN>
```

第一帧注册适配器：

```json
{
  "type": "register",
  "platform": "task-api",
  "capabilities": ["text", "file", "image", "preview", "update_message"]
}
```

每个任务消息必须显式指定 project。多项目场景下不要只依赖 `register.project`：当前 Bridge 实现按消息的 `project` 字段路由。

```json
{
  "type": "message",
  "project": "dianzhan-codex",
  "msg_id": "job-001",
  "session_key": "task-api:dianzhan:job-001",
  "user_id": "scheduler",
  "user_name": "scheduler",
  "reply_ctx": "job-001",
  "content": "检查当前仓库的测试失败原因并修复。"
}
```

将 `project` 改为 `dianzhan-claude` 即可调度 Claude Code。同一 `session_key` 会复用会话；不同任务应使用不同的 `job-*` 值。

适配器会收到 `reply`、`reply_stream`、`image`、`file` 等 Bridge 事件。完整协议见 `docs/bridge-protocol.zh-CN.md`。

## Skills

把 Skill 放在 `${SKILLS_DIR}` 的一级子目录，格式如下：

```text
deploy/bridge/skills/
└── review-pr/
    └── SKILL.md
```

该目录在容器内以只读方式挂载到 `/skills`，启动脚本同时链接到 Claude 与 Codex 的原生 Skills 路径。变更 Skill 后重启容器：

```bash
docker compose --env-file deploy/bridge/.env -f docker-compose.bridge.yml restart
```

## 运行边界

- 两个 project 共享 `dianzhan` 工作目录，但会话历史按 project 隔离。
- Claude 使用 `bypassPermissions`，Codex 使用 `full-auto`；两者都会自动执行工具调用。
- 这是逻辑隔离而非强文件系统隔离。不要挂载 Docker Socket、宿主机根目录、SSH 私钥或其他租户目录。
- `ANTHROPIC_API_KEY`、`OPENAI_API_KEY`、两个 Base URL 与 `CC_BRIDGE_TOKEN` 只存在于环境变量/本地 `.env`，不得提交。
