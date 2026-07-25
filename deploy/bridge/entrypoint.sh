#!/bin/sh
set -eu

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"
: "${ANTHROPIC_BASE_URL:?ANTHROPIC_BASE_URL is required}"
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required}"
: "${OPENAI_BASE_URL:?OPENAI_BASE_URL is required}"
: "${CC_BRIDGE_TOKEN:?CC_BRIDGE_TOKEN is required}"

mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$HOME/.agents"

managed_skill_marker=".cc-connect-source"

is_source_skill() {
    [ -d "$1" ] && [ ! -L "$1" ] && [ -f "$1/SKILL.md" ]
}

is_managed_skill_copy() {
    [ -d "$1" ] &&
        [ ! -L "$1" ] &&
        [ -f "$1/$managed_skill_marker" ] &&
        [ "$(cat "$1/$managed_skill_marker")" = "$2" ]
}

sync_skills() {
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

    # Remove stale entries managed by this entrypoint. Native CLI content such
    # as Codex's .system directory has no marker and is left untouched.
    for destination in "$target"/* "$target"/.[!.]* "$target"/..?*; do
        [ -e "$destination" ] || [ -L "$destination" ] || continue
        skill_name=${destination##*/}
        source="/skills/$skill_name"

        if [ -L "$destination" ]; then
            case "$(readlink "$destination")" in
                /skills/*)
                    is_source_skill "$source" || rm "$destination"
                    ;;
            esac
            continue
        fi

        if is_managed_skill_copy "$destination" "$source" && ! is_source_skill "$source"; then
            rm -rf "$destination"
        fi
    done

    # Some CLIs intentionally ignore skill directories that resolve outside
    # their native root. Copy each shared skill from the read-only template
    # mount so Codex and Claude Code see ordinary directories after restart.
    for source in /skills/* /skills/.[!.]* /skills/..?*; do
        is_source_skill "$source" || continue
        skill_name=${source##*/}
        [ "$skill_name" = ".system" ] && continue

        destination="$target/$skill_name"
        if [ -L "$destination" ]; then
            if [ "$(readlink "$destination")" != "$source" ]; then
                echo "refusing to replace unexpected shared skill link: $destination" >&2
                exit 1
            fi
        elif [ -e "$destination" ] && ! is_managed_skill_copy "$destination" "$source"; then
            echo "refusing to replace existing skill path: $destination" >&2
            exit 1
        fi

        temporary="$(mktemp -d "$target/.cc-connect-skill.XXXXXX")"
        cp -R "$source/." "$temporary/"
        printf '%s\n' "$source" > "$temporary/$managed_skill_marker"

        if [ -L "$destination" ]; then
            rm "$destination"
        elif [ -e "$destination" ]; then
            rm -rf "$destination"
        fi
        mv "$temporary" "$destination"
    done
}

remove_shared_skills() {
    target="$1"

    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" != "/skills" ]; then
            echo "refusing to replace unexpected skills link: $target" >&2
            exit 1
        fi
        rm "$target"
    elif [ -e "$target" ] && [ ! -d "$target" ]; then
        echo "refusing to replace non-directory skills path: $target" >&2
        exit 1
    fi

    mkdir -p "$target"
    for destination in "$target"/* "$target"/.[!.]* "$target"/..?*; do
        [ -e "$destination" ] || [ -L "$destination" ] || continue
        skill_name=${destination##*/}
        source="/skills/$skill_name"

        if [ -L "$destination" ]; then
            case "$(readlink "$destination")" in
                /skills/*) rm "$destination" ;;
            esac
        elif is_managed_skill_copy "$destination" "$source"; then
            rm -rf "$destination"
        fi
    done
}

compute_skills_revision() {
    manifest="$(mktemp)"
    for source in /skills/* /skills/.[!.]* /skills/..?*; do
        is_source_skill "$source" || continue
        find "$source" -type f -exec sha256sum {} \; >> "$manifest"
    done
    LC_ALL=C sort "$manifest" -o "$manifest"
    checksum="$(sha256sum "$manifest")"
    rm -f "$manifest"
    printf '%s\n' "${checksum%% *}"
}

# Each CLI gets real, writable directories under /data. /skills remains the
# read-only source of truth and is synchronized on every container start.
sync_skills "$CLAUDE_CONFIG_DIR/skills"
sync_skills "$HOME/.agents/skills"

# Codex discovers user Skills through $HOME/.agents/skills. Keep its private
# root for CLI-managed content such as .system, and migrate shared copies made
# by older entrypoints so the same Skill is not injected twice.
remove_shared_skills "$CODEX_HOME/skills"

# Native Agent threads capture their Skill list at creation time. Export a
# deterministic content revision so cc-connect can detach persisted sessions
# whenever a Skill is added, changed, or removed.
CC_SKILLS_REVISION="$(compute_skills_revision)"
export CC_SKILLS_REVISION

exec "$@"
