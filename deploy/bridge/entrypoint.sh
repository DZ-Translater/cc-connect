#!/bin/sh
set -eu

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"
: "${ANTHROPIC_BASE_URL:?ANTHROPIC_BASE_URL is required}"
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required}"
: "${OPENAI_BASE_URL:?OPENAI_BASE_URL is required}"
: "${CC_BRIDGE_TOKEN:?CC_BRIDGE_TOKEN is required}"

mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$HOME/.agents"

prepare_skills() {
    target="$1"
    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" != "/skills" ]; then
            echo "refusing to replace unexpected skills link: $target" >&2
            exit 1
        fi
        # Migrate the previous whole-directory link. Codex now installs its
        # built-in skills below this root, so the root itself must be writable.
        rm "$target"
    elif [ -e "$target" ] && [ ! -d "$target" ]; then
        echo "refusing to replace non-directory skills path: $target" >&2
        exit 1
    fi

    mkdir -p "$target"

    # Remove only dangling links managed by this entrypoint. This makes a
    # deleted shared skill disappear after a container restart without
    # touching CLI-managed files such as Codex's .system directory.
    for destination in "$target"/* "$target"/.[!.]* "$target"/..?*; do
        [ -L "$destination" ] || continue
        case "$(readlink "$destination")" in
            /skills/*)
                [ -e "$destination" ] || rm "$destination"
                ;;
        esac
    done

    # /skills is a read-only template mount. Link each shared skill into a
    # writable native root, leaving .system for each CLI to manage itself.
    for source in /skills/* /skills/.[!.]* /skills/..?*; do
        [ -e "$source" ] || [ -L "$source" ] || continue
        skill_name=${source##*/}
        [ "$skill_name" = ".system" ] && continue

        destination="$target/$skill_name"
        if [ -L "$destination" ]; then
            if [ "$(readlink "$destination")" = "$source" ]; then
                continue
            fi
            echo "refusing to replace unexpected shared skill link: $destination" >&2
            exit 1
        fi
        if [ -e "$destination" ]; then
            echo "refusing to replace existing skill path: $destination" >&2
            exit 1
        fi
        ln -s "$source" "$destination"
    done
}

# Each CLI gets a writable native skill root under /data. Shared skills remain
# read-only because only their top-level entries link to the /skills mount.
prepare_skills "$CLAUDE_CONFIG_DIR/skills"
prepare_skills "$CODEX_HOME/skills"
prepare_skills "$HOME/.agents/skills"

exec "$@"
