# syntax=docker/dockerfile:1

FROM golang:1.25-bookworm AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# This deployment is Bridge-only and needs only the Claude Code and Codex
# adapters. Excluding other plugins avoids compiling unused SDKs into the image.
ARG BUILD_TAGS="no_web no_acp no_antigravity no_copilot no_cursor no_devin no_gemini no_iflow no_kimi no_opencode no_pi no_qoder no_reasonix no_tmux no_cloud_web no_dingtalk no_discord no_feishu no_line no_matrix no_max no_qq no_qqbot no_slack no_telegram no_webex no_wecom no_weibo no_weixin no_wps_agentspace no_wps_xiezuo no_yuanbao"
RUN CGO_ENABLED=0 go build -trimpath -tags "$BUILD_TAGS" -ldflags="-s -w" -o /out/cc-connect ./cmd/cc-connect

FROM node:22-bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates curl git tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 agent \
    && useradd --system --uid 10001 --gid agent --create-home --home-dir /home/agent --shell /bin/bash agent \
    && npm install --global --omit=dev @anthropic-ai/claude-code @openai/codex \
    && npm cache clean --force

COPY --from=build /out/cc-connect /usr/local/bin/cc-connect
COPY deploy/bridge/entrypoint.sh /usr/local/bin/cc-connect-bridge-entrypoint

RUN mkdir -p /app/config /data/claude /data/codex /data/home/.agents /skills /workspace/dianzhan \
    && chown -R agent:agent /app /data /workspace /home/agent \
    && chmod 0755 /usr/local/bin/cc-connect-bridge-entrypoint

USER agent
WORKDIR /workspace/dianzhan

ENV HOME=/data/home \
    CLAUDE_CONFIG_DIR=/data/claude \
    CODEX_HOME=/data/codex \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 9810

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD test "$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:9810/bridge/ws)" = "401"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cc-connect-bridge-entrypoint"]
CMD ["cc-connect", "--config", "/app/config/config.toml"]
