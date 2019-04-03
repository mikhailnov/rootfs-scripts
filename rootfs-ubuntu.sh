#!/bin/bash -e
# Creates a systemd-nspawn container with Ubuntu

CODENAME=bionic


if [ $UID -ne 0 ]; then
	echo "run this script as root" >&2
	exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <destination>" >&2
	exit 0
fi

dest="$1"
rootfs=$(mktemp)

wget "http://cloud-images.ubuntu.com/${CODENAME}/current/${CODENAME}-server-cloudimg-amd64-root.tar.xz" -O $rootfs
mkdir -p "$dest"
tar -xaf $rootfs -C "$dest"

sed '/^root:/ s|\*||' -i "$dest/etc/shadow"
rm "$dest/etc/resolv.conf" "$dest/etc/securetty"
disable="ebtables rsync systemd-timesyncd snapd snapd.seeded"
disable="$disable networkd-dispatcher systemd-networkd systemd-networkd-wait-online systemd-resolved"
for s in $disable; do
	rm -f "$dest/etc/systemd/system/"*.target.wants"/$s.service" "$dest"/etc/rc[S5].d/S??"$s"
done
# ssh and iscsi cause startup to hang
systemd-nspawn -q -D "$dest" apt-get -qq purge -y openssh-server open-iscsi


rm $rootfs
echo ""
echo "Ubuntu $CODENAME container was created successfully."