#!/bin/sh
set -eu
case "${1:-}" in
    '') apply=no ;;
    --apply) apply=yes ;;
    -h|--help) echo "Usage: $0 [--apply] (run as your desktop user)"; exit 0 ;;
    *) echo "Usage: $0 [--apply]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo 'Too many arguments' >&2; exit 2; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${HOME:?HOME must be set}"

if [ "$apply" = no ]; then
    printf 'DRY RUN: would install settings into %s:\n' "$HOME"
    printf '  %s\n' .xinitrc .icewm/menu .icewm/toolbar
    echo 'Existing differing files are preserved and block --apply.'
    exit 0
fi
[ "$(id -u)" != 0 ] || { echo 'Run as your normal desktop user, without sudo.' >&2; exit 1; }
[ -d "$HOME" ] || { echo 'HOME must be an existing directory.' >&2; exit 1; }
# Refuse symlinked locations as well as differing content before writing anything.
[ ! -L "$HOME/.icewm" ] || { echo 'Refusing symlinked .icewm directory.' >&2; exit 1; }
if [ -e "$HOME/.icewm" ] && [ ! -d "$HOME/.icewm" ]; then
    echo '.icewm exists but is not a directory.' >&2; exit 1
fi
for file in .xinitrc .icewm/menu .icewm/toolbar; do
    case "$file" in
        .xinitrc) source="$root/config/xinitrc" ;;
        *) source="$root/config/icewm/${file##*/}" ;;
    esac
    target="$HOME/$file"
    if [ -L "$target" ] || { [ -e "$target" ] && ! cmp -s "$source" "$target"; }; then
        printf 'Preserving existing %s; review it before applying.\n' "$target" >&2
        exit 1
    fi
done
mkdir -p "$HOME/.icewm"
for file in .xinitrc .icewm/menu .icewm/toolbar; do
    case "$file" in
        .xinitrc) source="$root/config/xinitrc" ;;
        *) source="$root/config/icewm/${file##*/}" ;;
    esac
    if [ ! -e "$HOME/$file" ]; then
        # noclobber protects files created since preflight.
        (umask 077; set -C; cat "$source" > "$HOME/$file")
    fi
done
chmod u+x "$HOME/.xinitrc"
echo 'Settings installed. From a local console, run startx as this user.'
