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
mkdir -p "$test_root/skills/example-skill/references" "$test_root/skills/removed-skill"
printf '%s\n' '---' 'name: example-skill' '---' 'version one' > "$test_root/skills/example-skill/SKILL.md"
printf '%s\n' 'reference one' > "$test_root/skills/example-skill/references/rules.md"
printf '%s\n' '---' 'name: removed-skill' '---' 'remove me' > "$test_root/skills/removed-skill/SKILL.md"
touch "$test_root/skills/.gitkeep"

# Model the persisted links created by the pre-fix entrypoint. The regression
# check below verifies that the migration replaces only these known links.
ln -s /skills "$test_root/data/claude/skills"
ln -s /skills "$test_root/data/codex/skills"
ln -s /skills "$test_root/data/home/.agents/skills"

docker run --rm \
    -v "$test_root/data:/data" \
    node:22-bookworm-slim \
    chown 10001:10001 /data /data/claude /data/codex /data/home /data/home/.agents

run_entrypoint() {
    verification="$1"
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
        /test-entrypoint /bin/sh -ceu "$verification"
}

run_entrypoint '
        for root in "$CLAUDE_CONFIG_DIR/skills" "$HOME/.agents/skills"; do
            test -d "$root"
            test ! -L "$root"
            test -d "$root/example-skill"
            test ! -L "$root/example-skill"
            test "$(cat "$root/example-skill/.cc-connect-source")" = "/skills/example-skill"
            grep -q "version one" "$root/example-skill/SKILL.md"
            grep -q "reference one" "$root/example-skill/references/rules.md"
            test -d "$root/removed-skill"
            test ! -e "$root/.gitkeep"
        done
        test -d "$CODEX_HOME/skills"
        test ! -L "$CODEX_HOME/skills"
        test ! -e "$CODEX_HOME/skills/example-skill"
        test ! -e "$CODEX_HOME/skills/removed-skill"
        if touch /skills/.cc-connect-regression-write 2>/dev/null; then
            rm -f /skills/.cc-connect-regression-write
            echo "shared skills mount unexpectedly writable" >&2
            exit 1
        fi
        mkdir "$CODEX_HOME/skills/.system"
        touch "$CODEX_HOME/skills/.system/installed"
        test -f "$CODEX_HOME/skills/.system/installed"
        test -n "$CC_SKILLS_REVISION"
        printf "%s\n" "$CC_SKILLS_REVISION" > /data/skills-revision-initial
    '

# An unchanged restart must produce the same revision.
run_entrypoint '
        test "$CC_SKILLS_REVISION" = "$(cat /data/skills-revision-initial)"
        test -f "$CODEX_HOME/skills/.system/installed"
    '

printf '%s\n' '---' 'name: example-skill' '---' 'version two' > "$test_root/skills/example-skill/SKILL.md"

run_entrypoint '
        test "$CC_SKILLS_REVISION" != "$(cat /data/skills-revision-initial)"
        printf "%s\n" "$CC_SKILLS_REVISION" > /data/skills-revision-modified
        grep -q "version two" "$CLAUDE_CONFIG_DIR/skills/example-skill/SKILL.md"
        grep -q "version two" "$HOME/.agents/skills/example-skill/SKILL.md"
        test ! -e "$CODEX_HOME/skills/example-skill"
    '

mkdir -p "$test_root/skills/added-skill"
printf '%s\n' '---' 'name: added-skill' '---' 'added later' > "$test_root/skills/added-skill/SKILL.md"

run_entrypoint '
        test "$CC_SKILLS_REVISION" != "$(cat /data/skills-revision-modified)"
        printf "%s\n" "$CC_SKILLS_REVISION" > /data/skills-revision-added
        for root in "$CLAUDE_CONFIG_DIR/skills" "$HOME/.agents/skills"; do
            grep -q "version two" "$root/example-skill/SKILL.md"
            test -d "$root/added-skill"
            test ! -L "$root/added-skill"
            test "$(cat "$root/added-skill/.cc-connect-source")" = "/skills/added-skill"
        done
        test -f "$CODEX_HOME/skills/.system/installed"
        test ! -e "$CODEX_HOME/skills/added-skill"
    '

rm -rf "$test_root/skills/removed-skill"

run_entrypoint '
        test "$CC_SKILLS_REVISION" != "$(cat /data/skills-revision-added)"
        for root in "$CLAUDE_CONFIG_DIR/skills" "$HOME/.agents/skills"; do
            test ! -e "$root/removed-skill"
            test -d "$root/example-skill"
            test -d "$root/added-skill"
        done
        test -f "$CODEX_HOME/skills/.system/installed"
        test ! -e "$CODEX_HOME/skills/removed-skill"
    '
