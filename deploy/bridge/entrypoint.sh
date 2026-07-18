#!/bin/sh
set -eu

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"
: "${ANTHROPIC_BASE_URL:?ANTHROPIC_BASE_URL is required}"
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required}"
: "${OPENAI_BASE_URL:?OPENAI_BASE_URL is required}"
: "${CC_BRIDGE_TOKEN:?CC_BRIDGE_TOKEN is required}"

mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$HOME/.agents"

link_skills() {
    target="$1"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "refusing to replace non-symlink skills directory: $target" >&2
        exit 1
    fi
    ln -sfn /skills "$target"
}

# Each CLI scans its native skill root. A shared read-only bind mount makes
# one host directory available to both agents after the next container start.
link_skills "$CLAUDE_CONFIG_DIR/skills"
link_skills "$CODEX_HOME/skills"
link_skills "$HOME/.agents/skills"

exec "$@"
