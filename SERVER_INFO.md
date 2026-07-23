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

## Admin Gateway Network

The tracked Bridge Compose file also joins the external, internal-only
`cc-connect-bridge-api` network. Create it once before the first deployment:

```bash
docker network create --internal cc-connect-bridge-api
```

Only a server-side gateway such as `web-plugin` may join this network. Keep
the Bridge port bound to loopback, and provision its token to that gateway in a
separate mode-`0600` runtime file. Never expose `CC_BRIDGE_TOKEN` to a browser
or add it to an application image.

## Image Publishing And Updates

`.github/workflows/docker-bridge.yml` publishes
`ghcr.io/dz-translater/cc-connect-bridge` to GHCR on pushes to `dianzhan`.
Deploy only the immutable `image@sha256` reference emitted by the successful
workflow, never `latest` or another mutable tag. The server must pull that
reference with a dedicated read-only GHCR credential and never build locally.
