#!/bin/sh
# Creates a systemd-nspawn container with Ubuntu
# Fork of https://gist.github.com/sfan5/52aa53f5dca06ac3af30455b203d3404
set -xefu

CODENAME="${CODENAME:-bionic}"
ARCH="${ARCH:-amd64}"

if [ "$UID" -ne 0 ]; then
	echo "run this script as root" >&2
	exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <destination>" >&2
	exit 0
fi

dest="${dest:-$1}"
rootfs="${rootfs:-$(mktemp)}"

mkdir -p "$dest"
wget "http://cloud-images.ubuntu.com/${CODENAME}/current/${CODENAME}-server-cloudimg-amd64-root.tar.xz" -O "$rootfs"
tar -xaf "$rootfs" -C "$dest"

# allow logging in as root with no password via tty (systemd-nspawn)
cp "$dest/etc/shadow" "$dest/etc/shadow.bak"
sed '/^root:/ s|\*||' -i "$dest/etc/shadow"
cp "$dest/etc/securetty" "$dest/etc/securetty.bak"
#rm "$dest/etc/resolv.conf" "$dest/etc/securetty"
# disable apport
cp -v "$dest/etc/default/apport" "$dest/etc/default/apport.bak"
sed -i -e 's,enabled=1,enabled=0,g' "$dest/etc/default/apport"

disable="ebtables rsync systemd-timesyncd"
disable="$disable networkd-dispatcher systemd-networkd systemd-networkd-wait-online systemd-resolved"
for s in $disable; do
	( set +f
	rm -f "$dest/etc/systemd/system/"*.target.wants"/$s.service" "$dest"/etc/rc[S5].d/S??"$s"
	)
done
# we don't need these packages in systemd-nspawn
# polkit is potentially insecure and is not needed
# see dpkg -l and systemctl list-unit-files | grep enabled to find not needed packages
systemd-nspawn -q -D "$dest" apt autoremove --purge -y --allow-remove-essential \
	"libpolkit*" \
	cloud-guest-utils "cloud-init*" \
	snapd \
	"command-not-found*" \
	xfsprogs "btrfs-*" e2fsprogs lvm2 open-iscsi \
	unattended-upgrades \
	irqbalance \
	lxd "lxc*" pollinate \
	ufw \
	rsyslog
systemd-nspawn -q -D "$dest" apt update
systemd-nspawn -q -D "$dest" apt dist-upgrade -y
systemd-nspawn -q -D "$dest" apt install -y ncdu

rm -rf "$rootfs"
echo ""
echo "Ubuntu $CODENAME container was created successfully in ${dest}."
