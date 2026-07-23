# CC-Connect Bridge 接入交接

本文是 `dianzhan` 部署的外部程序接入说明。Bridge 不是某个 IM 软件的 API
适配器；任何能使用 WebSocket 的程序都可以作为适配器接入，并把任务路由给
Claude Code 或 Codex。

完整的通用消息 Schema 见 [`docs/bridge-protocol.zh-CN.md`](docs/bridge-protocol.zh-CN.md)。
本文只记录当前服务器、当前项目和实际接入时必须遵守的约定。

## 1. 连接地址

当前服务运行在 `by` 的 `127.0.0.1:9810`，因此外部机器不能直接访问这个端口。
推荐先建立 SSH 隧道：

```bash
ssh -N -L 9810:127.0.0.1:9810 by
```

保持隧道运行，然后把客户端连接到：

```text
ws://127.0.0.1:9810/bridge/ws
```

也可以把 Bridge 放到可信的 TLS 反向代理后，再使用代理的 `wss://` 地址。不要
直接把 Bridge 端口暴露到公网。

认证使用服务器 `.env` 中的 `CC_BRIDGE_TOKEN`。优先使用请求头，避免 Token 出现在
代理访问日志或 shell 历史中：

```text
Authorization: Bearer <CC_BRIDGE_TOKEN>
```

Bridge 也接受 `X-Bridge-Token` 请求头和 URL 的 `?token=` 查询参数。未认证请求返回
HTTP `401`。

## 2. 项目路由

当前只预建一个租户 `dianzhan`，但配置中有两个 Agent 项目：

| `project` | Agent | 用途 |
|---|---|---|
| `dianzhan-claude` | Claude Code | Claude 编码任务 |
| `dianzhan-codex` | Codex | Codex 编码任务 |

每一条 `message` 或 `card_action` 都应显式填写 `project`。不要依赖默认路由，尤其是
两个 Agent 同时存在时。

两个项目共享容器内的 `/workspace/dianzhan` 工作目录；会话历史按 `session_key`
隔离。当前部署是逻辑隔离，不是两个独立容器或独立文件系统。

## 3. WebSocket 协议

### 3.1 注册

连接建立后，第一帧必须是 `register`。`platform` 是外部程序的唯一名称，同一个
`platform` 的新连接会替换旧连接，因此多个实例应使用不同名称。能力按实际支持情况
声明；只做文本任务时声明 `text` 即可。需要把一条请求同步等待到完整 Agent
回复的 BFF 还应声明 `turn_completion`，并等待下面的 `reply_done` 终态事件。

```json
{
  "type": "register",
  "platform": "task-api",
  "capabilities": ["text"],
  "metadata": {
    "client": "my-scheduler",
    "version": "1.0.0"
  }
}
```

服务端会返回：

```json
{"type":"register_ack","ok":true}
```

### 3.2 发送任务

`session_key` 应稳定表示一个外部会话。建议使用 `platform:tenant:conversation` 格式，
并保证同一对话始终复用同一个值；不同任务要使用不同的会话值，或通过 REST API 创建
和切换命名会话。

```json
{
  "type": "message",
  "project": "dianzhan-codex",
  "msg_id": "job-001",
  "session_key": "task-api:dianzhan:job-001",
  "user_id": "scheduler",
  "user_name": "scheduler",
  "reply_ctx": "job-001",
  "model": "waninter-openai/gpt-5.3-codex-spark",
  "content": "检查当前仓库的测试失败原因并修复。"
}
```

字段约定：

- `project` 必须是 `dianzhan-claude` 或 `dianzhan-codex`。
- `msg_id` 用于调用方追踪，建议全局唯一。
- `model` 可选，填写上游返回的完整模型 ID。选择会按 `session_key` 保存并在
  后续恢复时继续使用，不会修改同项目其他会话的默认模型。
- `reply_ctx` 是调用方自己的不透明值，服务端会在回复中原样返回；不要把它当作
  Agent 会话 ID。
- 图片、文件和音频使用 Base64，结构见完整协议文档。单条消息最多 5 个附件，
  单个最大 10 MiB、解码后合计最大 25 MiB；任一附件无效会拒绝整条消息。

### 3.3 接收回复

客户端必须持续读取同一条 WebSocket 连接。最小文本适配器只需处理 `reply`：

```json
{
  "type": "reply",
  "session_key": "task-api:dianzhan:job-001",
  "reply_ctx": "job-001",
  "content": "已完成修复，测试全部通过。",
  "format": "text"
}
```

声明 `preview`（并实际处理 `preview_start`、`preview_ack`、`reply_stream`）后，可以
接收增量输出。否则服务端会发送最终的 `reply`，不会要求客户端实现流式更新。

对于网页 BFF、任务 API 等必须可靠拿到整条最终回复的调用方，在注册时声明
`turn_completion`，并忽略同一 `reply_ctx` 的中间或分片 `reply`，直到收到：

```json
{
  "type": "reply_done",
  "session_key": "task-api:dianzhan:job-001",
  "reply_ctx": "job-001",
  "content": "完整最终输出",
  "format": "text",
  "ok": true
}
```

失败时 `reply_done` 会携带 `"ok": false` 和安全的 `error` 文本，不会暴露 Agent、文件
系统或凭证细节。未声明该能力的既有适配器不会收到 `reply_done`，继续只处理 `reply`
即可。完整 Schema 见协议文档。

当适配器只声明文本能力时，权限或提问卡片会降级成直接文本 `reply`，随后也会发送
`reply_done`，以结束当前 HTTP 任务；用户下一条普通文本消息会作为该交互的回答进入
同一 `session_key`。需要卡片内点击交互的适配器必须实现 `buttons` 和 `card_action`。

其他常见服务端事件：

- `card`：富卡片；不支持 `card` 时服务端会降级为文本回复。
- `buttons`：按钮消息；点击后客户端发送 `card_action`。
- `typing_start` / `typing_stop`：输入状态。
- `image` / `file` / `audio`：二进制内容以 Base64 传输。
- `error`：服务端错误通知。

### 3.4 卡片操作和权限

客户端把按钮点击转换为：

```json
{
  "type": "card_action",
  "project": "dianzhan-codex",
  "session_key": "task-api:dianzhan:job-001",
  "action": "perm:allow",
  "reply_ctx": "job-001"
}
```

权限按钮的 `action` 当前支持 `perm:allow`、`perm:deny` 和 `perm:allow_all`；命令按钮
使用 `cmd:/命令`，例如 `cmd:/new`。`reply_ctx` 必须使用触发按钮的原值。

### 3.5 心跳和重连

每 30 秒发送一次应用层心跳：

```json
{"type":"ping","ts":1710000000000}
```

服务端返回 `pong`。超过约 90 秒没有读到数据连接会被关闭。断线后应使用指数退避
（建议 1 秒起步、最大 60 秒）重连，并重新发送 `register`；会话状态由 cc-connect
保留。

## 4. 可直接运行的 Python 示例

依赖：`pip install websockets`。把 Token 放在调用方的密钥管理中，不要提交到代码库。

```python
import asyncio
import json
import os

import websockets


WS_URL = os.environ.get("CC_BRIDGE_URL", "ws://127.0.0.1:9810/bridge/ws")
TOKEN = os.environ["CC_BRIDGE_TOKEN"]


async def main():
    async with websockets.connect(
        WS_URL,
        additional_headers={"Authorization": f"Bearer {TOKEN}"},
        ping_interval=None,  # 使用下面的 Bridge 应用层 ping
    ) as ws:
        await ws.send(json.dumps({
            "type": "register",
            "platform": "task-api-example",
            "capabilities": ["text"],
        }))
        ack = json.loads(await ws.recv())
        if not ack.get("ok"):
            raise RuntimeError(ack.get("error", "register failed"))

        await ws.send(json.dumps({
            "type": "message",
            "project": "dianzhan-codex",
            "msg_id": "example-001",
            "session_key": "task-api-example:dianzhan:example-001",
            "user_id": "example-client",
            "user_name": "example-client",
            "reply_ctx": "example-001",
            "content": "列出当前工作区的顶层文件，并用一句话总结。",
        }))

        async def heartbeat():
            while True:
                await asyncio.sleep(30)
                await ws.send(json.dumps({"type": "ping"}))

        heartbeat_task = asyncio.create_task(heartbeat())
        try:
            async for raw in ws:
                event = json.loads(raw)
                if event.get("type") == "reply":
                    print(event["content"])
                    break  # 真实客户端应继续读取并处理后续事件
                if event.get("type") == "error":
                    raise RuntimeError(event)
        finally:
            heartbeat_task.cancel()


asyncio.run(main())
```

## 5. 模型与会话 REST API

REST API 与 WebSocket 使用同一个端口和 Token。所有响应都是：

```json
{"ok": true, "data": {}}
{"ok": false, "error": "..."}
```

示例使用 `curl` 的 `Authorization` 请求头。`session_key` 放在 URL 时需要 URL 编码：

```bash
export BRIDGE=http://127.0.0.1:9810
export SESSION_KEY='task-api-example:dianzhan:example-001'
export PROJECT=dianzhan-codex

# 获取上游模型列表；session_key 可选，用于返回该会话当前选择
curl -sS -H "Authorization: Bearer ${CC_BRIDGE_TOKEN}" \
  --get "${BRIDGE}/bridge/models" \
  --data-urlencode "project=${PROJECT}" \
  --data-urlencode "session_key=${SESSION_KEY}"

# 列出会话
curl -sS -H "Authorization: Bearer ${CC_BRIDGE_TOKEN}" \
  "${BRIDGE}/bridge/sessions?project=${PROJECT}&session_key=${SESSION_KEY}"

# 创建命名会话
curl -sS -X POST -H "Authorization: Bearer ${CC_BRIDGE_TOKEN}" \
  -H 'Content-Type: application/json' \
  "${BRIDGE}/bridge/sessions" \
  -d "{\"project\":\"${PROJECT}\",\"session_key\":\"${SESSION_KEY}\",\"name\":\"work\"}"

# 读取会话历史（把 s2 换成真实会话 ID）
curl -sS -H "Authorization: Bearer ${CC_BRIDGE_TOKEN}" \
  "${BRIDGE}/bridge/sessions/s2?project=${PROJECT}&session_key=${SESSION_KEY}&history_limit=100"

# 切换活跃会话
curl -sS -X POST -H "Authorization: Bearer ${CC_BRIDGE_TOKEN}" \
  -H 'Content-Type: application/json' \
  "${BRIDGE}/bridge/sessions/switch" \
  -d "{\"project\":\"${PROJECT}\",\"session_key\":\"${SESSION_KEY}\",\"target\":\"s2\"}"

# 删除会话
curl -sS -X DELETE -H "Authorization: Bearer ${CC_BRIDGE_TOKEN}" \
  "${BRIDGE}/bridge/sessions/s2?project=${PROJECT}&session_key=${SESSION_KEY}"
```

生产调用方应对 `SESSION_KEY` 做 URL 编码，而不是直接拼接未经编码的用户输入。

## 6. 故障排查

```bash
# 服务状态（服务器上执行）
cd /srv/cc-connect
docker compose ps
docker inspect cc-connect-bridge \
  --format '{{if .State.Health}}{{.State.Health.Status}}{{end}} restarts={{.RestartCount}}'

# 未认证请求应为 401
curl -i http://127.0.0.1:9810/bridge/ws
```

- `401`：Token 未发送、错误，或反向代理没有转发认证头。
- `register_ack.ok=false`：注册帧不是第一帧，或 `platform` 为空。
- 连接成功但没有回复：检查消息中的 `project`、`session_key`、`user_id`，并确认项目
  名称拼写正确；多项目部署时必须显式指定 `project`。
- Codex 能回复纯文本、但读取附件或调用工具时报 `bwrap: No permissions to create a
  new namespace`：确认部署使用仓库中的 Compose 文件，并且容器的
  `SecurityOpt` 同时包含 `seccomp=unconfined`、`apparmor=unconfined` 和
  `no-new-privileges`；不要改用会绕过 Codex workspace 沙箱的 `yolo` 模式。
- 连接被关闭：确认客户端每 30 秒发送应用层 `ping`，并实现断线重连。
- 服务器重启后 Skills 变更未生效：在 `/srv/cc-connect/skills` 修改后执行
  `docker compose restart`。

不要在日志、工单或代码中记录 `CC_BRIDGE_TOKEN`、`ANTHROPIC_API_KEY` 或
`OPENAI_API_KEY`。
