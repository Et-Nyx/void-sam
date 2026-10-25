# void-sam

A minimal Void Linux x86_64 **glibc** + IceWM desktop for the Samsung
NP530XBB-AD2BR: Firefox, PCManFM, Zathura, PulseAudio and NetworkManager.
Hardware specifications must be verified on the actual notebook.

The [installation guide](VOID_ICEWM_SAMSUNG_530X_GUIDE.md) is included in this
repository. It covers the internal install and an optional external-SSD
rehearsal, including the USB-root initramfs and UEFI/BIOS boot requirements.
Read it before installing the OS. These scripts cover an initial post-install
setup; they do not partition disks, install a bootloader or migrate ChromeOS
Flex data.

## After installing Void

Back up your data and install the base system manually using the guide. Update
with `sudo xbps-install -Syu`, repeat if XBPS requests it, and reboot as needed.
Run all commands below from this checkout.

```sh
# Inspect the package/service plan on any Linux host; makes no changes.
./scripts/install-desktop.sh

# On the installed notebook only, install packages and enable runit services.
sudo ./scripts/install-desktop.sh --apply

# From your normal desktop user's account, preview then install user settings.
./scripts/configure-user.sh
./scripts/configure-user.sh --apply
```

The installer checks Void, architecture, glibc and root privileges before
applying. It refuses enabled `dhcpcd`, `wpa_supplicant` or `acpid` services;
review the guide and resolve competing network/power handlers yourself first.
It enables D-Bus, NetworkManager and elogind, but does not change user groups,
network credentials, disk swap, ZRAM, or power policy. If necessary, use
`sudo usermod -aG network YOUR_LOGIN` and log out/in before running `nmtui`.

User configuration installs `.xinitrc` and IceWM menu/toolbar files. Existing
identical files are accepted; differing files cause a refusal **before any
configuration is copied**. Review and move those files yourself if you want
these defaults. Run without sudo, then log into a local console and use `startx`.
No display manager or automatic X startup is configured.

## Validation

Development checks require only POSIX shell and Python 3 (standard library):

```sh
python3 -m unittest discover -s tests -v
```

These tests exercise simulation, platform guards, safe configuration installation
and repeated runs in temporary directories. They do not prove hardware support
or package availability in a current Void mirror. On the notebook, complete the
guide's post-install checklist: Wi-Fi after reboot, IceWM via `startx`, Firefox
audio, PDF opening, `vainfo`, brightness and suspend/resume. Install uBlock Origin
through Firefox manually. EPUB support, ZRAM, screen locking and power tuning
remain follow-up work; the starter menu has no lock command until a locker is
chosen and tested.
