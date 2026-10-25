#!/bin/sh
# Post-install only. Default mode prints a plan without modifying the host.
set -eu

case "${1:-}" in
    '') apply=no ;;
    --apply) apply=yes ;;
    -h|--help) echo "Usage: $0 [--apply] (default: dry run)"; exit 0 ;;
    *) echo "Usage: $0 [--apply]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo 'Too many arguments' >&2; exit 2; }

packages='xorg-minimal xinit icewm mesa-dri xf86-input-libinput dbus elogind NetworkManager firefox pcmanfm xterm dejavu-fonts-ttf intel-video-accel pulseaudio pavucontrol alsa-utils libva-utils zathura zathura-pdf-mupdf'
services='dbus NetworkManager elogind'

if [ "$apply" = no ]; then
    echo 'DRY RUN: no changes. On Void x86_64 glibc, after updating the base system:'
    echo "  xbps-install -Sy $packages"
    echo "  Enable runit services: $services"
    echo '  Refuse competing dhcpcd, wpa_supplicant or acpid service links.'
    echo 'Use --apply as root on the installed notebook to proceed.'
    exit 0
fi

fail() { echo "$*" >&2; exit 1; }
[ -r /etc/os-release ] || fail 'Cannot identify OS; requires Void Linux.'
. /etc/os-release
[ "${ID:-}" = void ] || fail 'Requires Void Linux; refusing to change this host.'
[ "$(uname -m)" = x86_64 ] || fail 'Requires x86_64.'
command -v getconf >/dev/null 2>&1 || fail 'Missing getconf; cannot verify glibc.'
case "$(getconf GNU_LIBC_VERSION 2>/dev/null || true)" in
    'glibc '*) ;;
    *) fail 'Requires glibc, not musl.' ;;
esac
[ "$(id -u)" = 0 ] || fail 'Run --apply as root (sudo).'
command -v xbps-install >/dev/null 2>&1 || fail 'Missing xbps-install.'
[ -d /var/service ] || fail 'Missing active runit service directory /var/service.'
for service in dhcpcd wpa_supplicant acpid; do
    if [ -e "/var/service/$service" ] || [ -L "/var/service/$service" ]; then
        fail "Review competing service /var/service/$service before applying (see guide)."
    fi
done
for service in $services; do
    target="/var/service/$service"
    if [ -e "$target" ] || [ -L "$target" ]; then
        [ -L "$target" ] && [ "$(readlink -f "$target")" = "/etc/sv/$service" ] ||
            fail "Unexpected service entry: $target; review manually."
    fi
done

# Intentional word splitting: the package list contains fixed package names only.
xbps-install -Sy $packages
for service in $services; do
    [ -d "/etc/sv/$service" ] || fail "Package did not supply /etc/sv/$service."
done
for service in $services; do
    if [ ! -e "/var/service/$service" ] && [ ! -L "/var/service/$service" ]; then
        ln -s "/etc/sv/$service" "/var/service/$service"
    fi
done
echo 'Packages installed; service links enabled. Verify service readiness:'
sv -w 15 up /var/service/dbus /var/service/NetworkManager /var/service/elogind
sv status /var/service/dbus /var/service/NetworkManager /var/service/elogind
echo 'Configure the normal user next; see README.md for login and hardware checks.'
