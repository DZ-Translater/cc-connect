# Server Deployment

## DianZhan Bridge Service

- Server: `ssh by`
- Deployment directory: `/srv/cc-connect`
- Service: `cc-connect-bridge`
- WebSocket endpoint: `ws://<server>:9810/bridge/ws`
- Tenant projects: `dianzhan-claude`, `dianzhan-codex`

The service is Bridge-only. It does not configure or expose an IM platform,
the management API, or the generic webhook server.

## Initial Deployment

The source and deployment files are staged at `/srv/cc-connect`. Configure
the secrets on the server before starting the service:

The contents of `deploy/bridge/` in the repository are copied directly into
`/srv/cc-connect`; no nested `deploy/bridge` directory is used on the server.

```bash
ssh by
cd /srv/cc-connect
cp .env.example .env
chmod 600 .env
# Set ANTHROPIC_API_KEY, ANTHROPIC_BASE_URL, OPENAI_API_KEY,
# OPENAI_BASE_URL, and CC_BRIDGE_TOKEN. Optional model and wire API settings
# are documented in .env.example.
```

The server never builds this image. Pull the GitHub Actions image first, then
start it:

```bash
docker compose pull
docker compose up -d
```

The Bridge port defaults to loopback. Set `BRIDGE_BIND_ADDR` in
`.env` only when a firewall and TLS reverse proxy protect the public endpoint.

## Image Publishing And Updates

`.github/workflows/docker-bridge.yml` publishes
`yzg963/cc-connect-bridge:latest` to Docker Hub on pushes to `dianzhan`. The
first workflow run requires this change to be committed and pushed.
