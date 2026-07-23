#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    # The test runs as UID 10001, so use Docker's root user to remove the
    # temporary bind-mount contents before the runner removes its temp dir.
    docker run --rm -v "$test_root:/test" node:22-bookworm-slim \
        rm -rf /test/data /test/skills >/dev/null 2>&1 || true
    rm -rf "$test_root"
}
trap cleanup EXIT INT TERM

mkdir -p "$test_root/data/claude" "$test_root/data/codex" "$test_root/data/home/.agents"
mkdir -p "$test_root/skills/example-skill"
printf '%s\n' '---' 'name: example-skill' '---' > "$test_root/skills/example-skill/SKILL.md"

# Model the persisted links created by the pre-fix entrypoint. The regression
# check below verifies that the migration replaces only these known links.
ln -s /skills "$test_root/data/claude/skills"
ln -s /skills "$test_root/data/codex/skills"
ln -s /skills "$test_root/data/home/.agents/skills"

docker run --rm \
    -v "$test_root/data:/data" \
    node:22-bookworm-slim \
    chown 10001:10001 /data /data/claude /data/codex /data/home /data/home/.agents

docker run --rm \
    --user 10001:10001 \
    --read-only \
    --tmpfs /tmp:mode=1777,size=64m \
    -v "$test_root/data:/data:rw" \
    -v "$test_root/skills:/skills:ro" \
    -v "$repo_root/deploy/bridge/entrypoint.sh:/test-entrypoint:ro" \
    -e ANTHROPIC_API_KEY=test \
    -e ANTHROPIC_BASE_URL=https://example.invalid \
    -e OPENAI_API_KEY=test \
    -e OPENAI_BASE_URL=https://example.invalid/v1 \
    -e CC_BRIDGE_TOKEN=test \
    -e HOME=/data/home \
    -e CLAUDE_CONFIG_DIR=/data/claude \
    -e CODEX_HOME=/data/codex \
    --entrypoint /bin/sh \
    node:22-bookworm-slim \
    /test-entrypoint /bin/sh -ceu '
        for root in "$CLAUDE_CONFIG_DIR/skills" "$CODEX_HOME/skills" "$HOME/.agents/skills"; do
            test -d "$root"
            test ! -L "$root"
            test -L "$root/example-skill"
            test "$(readlink "$root/example-skill")" = "/skills/example-skill"
        done
        if touch /skills/.cc-connect-regression-write 2>/dev/null; then
            rm -f /skills/.cc-connect-regression-write
            echo "shared skills mount unexpectedly writable" >&2
            exit 1
        fi
        mkdir "$CODEX_HOME/skills/.system"
        touch "$CODEX_HOME/skills/.system/installed"
        test -f "$CODEX_HOME/skills/.system/installed"
    '
