# Void Linux + IceWM: Samsung 530X installation guide

**Target:** Samsung NP530XBB-AD2BR (530X), currently running ChromeOS Flex  
**Intended use:** Web browsing, PDF/EPUB reading, and a lightweight traditional desktop  
**Approach:** Void Linux x86_64 **glibc**, Xorg, IceWM, runit; avoid unnecessary services.  
**Last reviewed:** 2026-10-25

> **Warning — destructive installation:** This guide replaces ChromeOS Flex and erases the internal disk when you repartition it. Back up your files before proceeding. Verify device names with `lsblk` before writing to any disk. Never paste example disk paths blindly.

## 1. Goals and hardware assumptions

The notebook is believed to have an Intel Celeron N4000, 4 GB RAM and roughly 128 GB eMMC storage, but **verify these in the live environment**; model configurations can vary. The practical bottleneck is modern websites, not the window manager. Aim for reliable hardware support and modest idle memory, not record-low idle RAM at the cost of functionality.

| Component | Choice | Reason |
|---|---|---|
| OS | Void x86_64 glibc | Standard compatibility and lean base |
| Init | runit | Void default |
| Window manager | IceWM | Familiar desktop and taskbar with little overhead |
| Graphics | Xorg modesetting + Mesa | Standard Intel open-source stack |
| Login | Text console + `startx` | No graphical login manager |
| Network | NetworkManager | Easy Wi-Fi administration |
| Sessions | D-Bus + elogind | Device access and power controls |
| Browser | Firefox + uBlock Origin | Browsing and content blocking |
| Documents | Zathura (PDF); EPUB reader as needed | Low overhead |
| Files | PCManFM | Traditional file manager |
| Filesystem | ext4 | Reliable, straightforward |
| Swap | ZRAM first; disk swap optional | Avoid frequent writes to eMMC |

## 2. Before erasing ChromeOS Flex

1. Back up Downloads, documents, bookmarks, passwords, and any files stored locally. Confirm you can access the backup from another device.
2. Download **Void Linux Base, x86_64, glibc** from <https://voidlinux.org/download/>. Verify the release's SHA-256 checksums and signature using the official instructions.
3. Write the ISO to a USB drive. If using another Linux machine, identify the USB using `lsblk -o NAME,SIZE,MODEL,TRAN` first. Writing an image with `dd` to the wrong device destroys data.
4. Boot the USB using the notebook's boot menu/UEFI firmware. Disable Secure Boot if it prevents the unsigned Void installer from booting; do not change other firmware settings unnecessarily.
5. **Test first:** keyboard, touchpad, Wi-Fi, screen brightness, sound device detection, and internal eMMC detection. Suspend/resume may require testing after installation.

From the Void live shell:

```sh
lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,MOUNTPOINTS
lscpu | grep -E 'Model name|Architecture'  # if lscpu is available
free -h
ip link
```

Typical eMMC names look like `/dev/mmcblk0`; the installer may also show `/dev/sda` or `/dev/nvme0n1`. **Do not assume any one name is correct.**

## 3. Install the base system

Boot the live image and log in with the credentials shown by the ISO (historically `root` / `voidlinux`). Then run:

```sh
void-installer
```

Installer selections:

- **Keyboard/locale/time zone:** Choose your actual settings (e.g., Brazilian Portuguese keyboard and America/Sao_Paulo if applicable).
- **Source:** `Network` when networking works; otherwise `Local`.
- **User:** Create a normal user; ensure it has administrative (`wheel`) access.
- **Partitioning:** UEFI + GPT if the firmware is booted in UEFI mode.
- **Bootloader:** GRUB on the internal disk, using the UEFI setup.

Suggested partition layout for a 128 GB disk:

| Partition | Size | Type | Filesystem | Mount point |
|---|---:|---|---|---|
| EFI System Partition | 512 MiB | EFI System | FAT32 / vfat | `/boot/efi` |
| Root | Rest of disk | Linux filesystem | ext4 | `/` |

No dedicated swap partition is required for an initial ZRAM-based setup. **Trade-off:** without sufficiently sized persistent swap, disk-backed swap, and suitable configuration, hibernation will not work. If hibernation is important, design disk swap *before* installation.

In the installer's partition editor, verify disk **capacity, name and existing ChromeOS Flex partitions** before selecting Write. Assign both mount points in the Filesystems step. Complete the installation, unplug the USB, and reboot.

Official installation steps: <https://docs.voidlinux.org/installation/live-images/guide.html>

## 4. First boot and package installation

Log in as the normal user. Update the system:

```sh
sudo xbps-install -Syu
```

If the update requests another pass (e.g. a package manager or libc transition), repeat until no outstanding updates remain, then reboot when appropriate.

Install a minimal desktop foundation:

```sh
sudo xbps-install -S \
  xorg-minimal xinit icewm \
  mesa-dri xf86-input-libinput \
  dbus elogind NetworkManager \
  firefox pcmanfm xterm \
  dejavu-fonts-ttf
```

Check package names with `xbps-query -Rs NAME` if repositories have changed. For Intel video acceleration install:

```sh
sudo xbps-install -S intel-video-accel
```

The kernel usually supplies Intel firmware dependencies through `linux-firmware-intel`. Do not install legacy `xf86-video-intel` unless the default modesetting driver is demonstrably problematic.

### Enable only essential runit services

First inspect current services:

```sh
ls -l /var/service/
```

NetworkManager must not compete with `dhcpcd`, `wpa_supplicant`, or another standalone network manager. **Only if the listed services are currently enabled and you intend to replace them**, disable their runit links:

```sh
sudo rm /var/service/dhcpcd       # only if it exists and is enabled
sudo rm /var/service/wpa_supplicant # only if it exists and is enabled
```

Then enable D-Bus, NetworkManager, and elogind, *if not already enabled*:

```sh
for service in dbus NetworkManager elogind; do
  if [ -d "/etc/sv/$service" ] && [ ! -e "/var/service/$service" ]; then
    sudo ln -s "/etc/sv/$service" "/var/service/$service"
  fi
done
```

`elogind` and `acpid` may both react to laptop lid/power events. If `acpid` is enabled, configure it not to duplicate those events or disable it after checking your hardware hotkeys:

```sh
ls -l /var/service/acpid
# If present and you choose elogind as the sole lid/power handler:
# sudo rm /var/service/acpid
```

Add the desktop user to the network group if necessary:

```sh
sudo usermod -aG network "$USER"
```

Reboot or log out and back in so groups and sessions refresh. Connect to Wi-Fi using:

```sh
nmtui
```

## 5. Start IceWM without a display manager

From your normal user account:

```sh
cat > ~/.xinitrc <<'EOF_XINIT'
#!/bin/sh
exec dbus-run-session icewm-session
EOF_XINIT
chmod +x ~/.xinitrc
startx
```

This starts IceWM with a session D-Bus bus. To boot graphically by choice, log in on the text console and run `startx`; do not enable a display manager unless needed.

Optional auto-start X **only for interactive logins on tty1** (append to `~/.profile` if using a compatible login shell):

```sh
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
  exec startx
fi
```

This is optional; manual `startx` makes troubleshooting easier.

## 6. Configure IceWM for practical desktop use

IceWM user settings typically live in `~/.icewm/`. If you need example files, inspect `/usr/share/icewm/` and copy only the files you want to modify; avoid replacing defaults wholesale.

Suggested user-experience setup:

- Keep IceWM's built-in taskbar, tray, clock, workspace switcher, and application menu.
- Use a simple non-animated theme and **no compositor** initially.
- Create a taskbar/menu shortcut for Firefox, PCManFM, and a terminal.
- Configure a keyboard shortcut for locking the screen once a lock utility is installed.
- Use NetworkManager's `nmtui` first; add `network-manager-applet` only if a tray GUI is desired.
- Start with default fonts; add `noto-fonts-ttf` if you encounter missing characters.

To inspect IceWM's configuration options and installed example files:

```sh
man icewm
find /usr/share/icewm -maxdepth 2 -type f | head -40
```

## 7. Sound, video, and documents

### Sound

Do not assume bare ALSA will be sufficient for Firefox on every installation. Test output first. For a convenient browser-compatible audio setup, choose **one** sound server: PulseAudio (simple automatic startup) or PipeWire (more flexible). Avoid installing and independently starting multiple competing sound servers.

A practical first attempt:

```sh
sudo xbps-install -S pulseaudio pavucontrol alsa-utils
```

Log back into the IceWM session, then test audio with Firefox or `speaker-test` (from `alsa-utils`). If opting for PipeWire instead, follow Void's official configuration before enabling it: <https://docs.voidlinux.org/config/media/pipewire.html>.

### Intel video

VA-API can reduce CPU usage for supported codecs:

```sh
sudo xbps-install -S libva-utils
vainfo
```

Verify driver initialization and supported decode profiles. You may need to configure Firefox video decoding separately; inspect `about:support` instead of assuming acceleration is active. YouTube's codec selection and browser settings strongly affect playback smoothness.

### Reading

```sh
sudo xbps-install -S zathura zathura-pdf-mupdf
```

Try opening local PDFs with `zathura document.pdf`. For EPUB files, select an EPUB reader available in the repositories; check `xbps-query -Rs foliate` before assuming a package is available. Firefox is also a practical fallback for some document formats, though dedicated apps often use fewer resources.

## 8. ZRAM: optional memory optimization

With 4 GB of RAM, ZRAM is worth testing. It creates a **compressed block device in RAM**, commonly used for swap. It can reduce slow eMMC swapping, but cannot fully substitute for more physical RAM.

Do **not** create a ZRAM device with a hard-coded `/dev/zram0` command until you check the current setup:

```sh
swapon --show
zramctl
cat /proc/swaps
```

For a temporary manual test, assuming `/dev/zram0` is available and unused and kernel module support is present:

```sh
sudo modprobe zram
sudo zramctl --find --size 2G --algorithm lz4
# Check the returned device name (typically /dev/zram0), then substitute below:
sudo mkswap /dev/zram0
sudo swapon -p 100 /dev/zram0
swapon --show
```

**Important:** `zramctl --find` may return a different device. Use that returned path rather than assuming `/dev/zram0`. The commands above are only for a **temporary test**; devices/configuration won't necessarily persist across reboot. For permanent configuration, use a maintained zram service/package supported by your installed Void version or configure an explicit runit service after confirming the temporary test behaves properly. Never initialize an existing device containing data.

Start around 2 GB logical compressed-swap size and observe behavior. ZRAM's configured size is not a reservation of that much physical RAM. If the machine still experiences out-of-memory crashes, consider adding a small disk swapfile as a fallback; that is a separate setup with eMMC wear/performance trade-offs.

## 9. Power management and eMMC hygiene

- Test suspend with `loginctl suspend` before configuring automatic lid behavior.
- With elogind, adjust `/etc/elogind/logind.conf` as needed for lid-close policies; test with AC power and battery.
- Avoid running simultaneous competing power managers or duplicate lid handlers.
- Use ext4 defaults first; do not add exotic filesystem tuning without measurable benefit.
- Check mount options and discard support before enabling scheduled trim. Not all eMMC devices expose the same capabilities.
- Keep enough free disk space for Firefox profiles, downloads, and package caches.

Void's official power-management reference: <https://docs.voidlinux.org/config/power-management.html>.

## 10. Post-install validation checklist

- [ ] Boots from internal storage without the USB installer.
- [ ] Wi-Fi reconnects after a reboot.
- [ ] `startx` opens IceWM without running as root.
- [ ] Keyboard, touchpad, scroll wheel, and brightness keys work.
- [ ] Firefox displays pages and plays sound.
- [ ] PDF reading works in Zathura.
- [ ] Video acceleration reports sensible VA-API profiles.
- [ ] Suspend and resume preserve Wi-Fi, audio, and display function.
- [ ] ZRAM or swap configuration is understood and verified with `swapon --show`.
- [ ] Browser memory consumption is manageable with a few typical tabs.

Useful diagnostics:

```sh
free -h
swapon --show
sv status /var/service/*
lsblk -f
ip addr
lspci -nnk   # if pciutils is installed
```

## 11. Common problems

**Boot fails after install:** Confirm USB was booted in UEFI mode, GPT partition layout, EFI System Partition mounted at `/boot/efi`, and GRUB installed. See <https://docs.voidlinux.org/installation/guides/chroot.html> for UEFI repair guidance.

**No Wi-Fi:** Inspect `ip link`, `lspci -nnk` or `lsusb`, and kernel logs. Identify the Wi-Fi chipset before downloading firmware. Confirm that no competing wireless manager remains enabled.

**`startx` fails:** Run `startx` as your normal user from a local TTY, verify `elogind` and `dbus`, and inspect Xorg logs and `~/.xinitrc`. Avoid random `chmod` changes to `/dev` devices.

**No audio:** Check output selection with `pavucontrol`, verify the chosen audio server and inspect ALSA cards using `aplay -l`.

**Video remains choppy:** Review `vainfo`, Firefox `about:support`, YouTube codec choice, CPU usage and thermals. Switching window managers cannot solve browser decode bottlenecks.

**Suspend resumes to a black display:** Temporarily disable automatic suspend/lid handling, confirm the machine is reachable by keyboard or network, and investigate GPU/ACPI logs. Do not assume a power-management tweak is universally safe.

## 12. Routine maintenance

Update regularly:

```sh
sudo xbps-install -Syu
```

Look at installed packages and enabled services before removing anything:

```sh
xbps-query -l
ls -l /var/service/
```

Back up your user configuration (`~/.icewm`, `~/.xinitrc`, browser profile/bookmarks, documents) periodically. Prefer reliability over aggressive cleanup: the size of the base system is rarely the limiting factor once Firefox is running.

## Official reference links

- Void downloads: <https://voidlinux.org/download/>
- Void Handbook: <https://docs.voidlinux.org/>
- Live-image installation: <https://docs.voidlinux.org/installation/live-images/guide.html>
- UEFI partitioning: <https://docs.voidlinux.org/installation/live-images/partitions.html>
- Xorg: <https://docs.voidlinux.org/config/graphical-session/xorg.html>
- Intel graphics: <https://docs.voidlinux.org/config/graphical-session/graphics-drivers/intel.html>
- NetworkManager: <https://docs.voidlinux.org/config/network/networkmanager.html>
- Session management: <https://docs.voidlinux.org/config/session-management.html>
- runit services: <https://docs.voidlinux.org/config/services/index.html>
- Sound: <https://docs.voidlinux.org/config/media/index.html>
- Power management: <https://docs.voidlinux.org/config/power-management.html>

---

**Guiding principle:** Use the smallest set of software that reliably supports the notebook's hardware and your browsing/reading workload. Measure problems before tuning.
