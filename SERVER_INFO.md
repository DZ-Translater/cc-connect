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

## Codex Sandbox Runtime

The Codex project runs in `full-auto` mode and uses the Codex CLI's bundled
`bwrap` workspace sandbox for shell tools. Docker's default seccomp and
AppArmor profiles prevent that nested namespace from starting, so the tracked
Compose service explicitly uses `seccomp=unconfined` and
`apparmor=unconfined`. Keep the remaining container boundaries in place:
non-root user, `cap_drop: ALL`, `no-new-privileges`, read-only root filesystem,
and only the declared writable volumes.

If those two options are removed, text-only replies may still work while file
reads and other tool calls fail with `bwrap: No permissions to create a new
namespace`. Validate the effective options after deployment:

```bash
docker inspect cc-connect-bridge \
  --format 'user={{.Config.User}} caps={{json .HostConfig.CapAdd}} security={{json .HostConfig.SecurityOpt}} readonly={{.HostConfig.ReadonlyRootfs}}'
```

## Updating Shared Skills

`/srv/cc-connect/skills` is the host-side source of truth and is mounted into
the container as read-only `/skills`. Put each Skill in its own directory with
a top-level `SKILL.md`, then restart the Bridge:

```bash
rsync -a --delete ./my-skill/ by:/srv/cc-connect/skills/my-skill/
ssh by 'cd /srv/cc-connect && docker compose restart cc-connect-bridge'
```

On every container start, the entrypoint copies valid Skills into the native
Claude Code directory and the cross-agent `$HOME/.agents/skills` root under
`/data`. Codex reads user Skills from the cross-agent root; its private
`$CODEX_HOME/skills` directory is reserved for CLI-managed content such as
`.system`, avoiding duplicate Skill discovery. Changed Skills are replaced and
deleted source Skills are removed. Do not edit the generated copies inside the
container because the next restart overwrites them.

The entrypoint also exports a deterministic `CC_SKILLS_REVISION`. When this
revision changes, cc-connect preserves each logical conversation, its visible
history, name, model, and provider, but starts a fresh native Codex/Claude
thread on the next message. Native threads capture their Skill list at creation
time, so this one-time refresh is required for newly copied Skills to appear in
existing Bridge conversations.

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
