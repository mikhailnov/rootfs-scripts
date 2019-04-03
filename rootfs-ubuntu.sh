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

cp "$dest/etc/shadow" "$dest/etc/shadow.bak"
sed '/^root:/ s|\*||' -i "$dest/etc/shadow"
cp "$dest/etc/securetty" "$dest/etc/securetty.bak"
#rm "$dest/etc/resolv.conf" "$dest/etc/securetty"

disable="ebtables rsync systemd-timesyncd snapd snapd.seeded"
disable="$disable networkd-dispatcher systemd-networkd systemd-networkd-wait-online systemd-resolved"
for s in $disable; do
	( set +f
	rm -f "$dest/etc/systemd/system/"*.target.wants"/$s.service" "$dest"/etc/rc[S5].d/S??"$s"
	)
done
# ssh and iscsi cause startup to hang
#systemd-nspawn -q -D "$dest" apt-get -qq purge -y openssh-server open-iscsi

rm -rf "$rootfs"
echo ""
echo "Ubuntu $CODENAME container was created successfully in ${dest}."
