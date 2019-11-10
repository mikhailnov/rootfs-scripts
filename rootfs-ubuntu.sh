#!/bin/sh
# Creates a systemd-nspawn container with Ubuntu
# Fork of https://gist.github.com/sfan5/52aa53f5dca06ac3af30455b203d3404

CODENAME="${CODENAME:-bionic}"
ARCH="${ARCH:-amd64}"
ADD_PPA="${ADD_PPA:-1}"

if [ "$(id -u)" -ne 0 ]; then
	echo "run this script as root" >&2
	exit 1
fi

set -xefu

if [ -z "$1" ]; then
	echo "Usage: $0 <destination>" >&2
	exit 0
fi

dest="${dest:-$1}"
rootfs="${rootfs:-$(mktemp)}"

mkdir -p "$dest"
wget "http://cloud-images.ubuntu.com/${CODENAME}/current/${CODENAME}-server-cloudimg-${ARCH}-root.tar.xz" -O "$rootfs"
tar -xaf "$rootfs" -C "$dest"
rm -f "$dest/etc/resolv.conf"
cat > "$dest/etc/resolv.conf" <<'EOF'
nameserver 8.8.8.8
nameserver 77.88.8.8
nameserver 8.8.4.4
nameserver 77.88.8.1
EOF

# allow logging in as root with no password via tty (systemd-nspawn)
cp "$dest/etc/shadow" "$dest/etc/shadow.bak"
sed '/^root:/ s|\*||' -i "$dest/etc/shadow"
cp "$dest/etc/securetty" "$dest/etc/securetty.bak"
#rm "$dest/etc/resolv.conf" "$dest/etc/securetty"
# disable apport
cp "$dest/etc/default/apport" "$dest/etc/default/apport.bak"
sed -i -e 's,enabled=1,enabled=0,g' "$dest/etc/default/apport"
# disable motd
cp "$dest/etc/pam.d/login" "$dest/etc/pam.d/login.bak"
sed -i -e '/motd/d' "$dest/etc/pam.d/login"

disable="ebtables rsync systemd-timesyncd"
disable="$disable networkd-dispatcher systemd-networkd systemd-networkd-wait-online systemd-resolved"
( set +f
for s in $disable; do
	rm -f "$dest/etc/systemd/system/"*.target.wants"/$s.service" "$dest"/etc/rc[S5].d/S??"$s"
done )

sed -i -e 's,archive.ubuntu.com,mirror.timeweb.ru,g' "$dest/etc/apt/sources.list"
# software-properties-common (add-apt-repository) will be delete afterwards with python3
if [ "$ADD_PPA" != 0 ]; then systemd-nspawn -q -D "$dest" add-apt-repository ppa:mikhailnov/utils -y -n; fi
systemd-nspawn -q -D "$dest" apt update
systemd-nspawn -q -D "$dest" apt dist-upgrade -y
# we don't need these packages in systemd-nspawn
# polkit is potentially insecure and is not needed
# see dpkg -l and systemctl list-unit-files | grep enabled to find not needed packages
systemd-nspawn -q -D "$dest" apt autoremove --purge -y --allow-remove-essential \
	"libpolkit*" \
	cloud-guest-utils "cloud-init*" \
	snapd \
	"command-not-found*" \
	xfsprogs "btrfs-*" "ntfs-*" "initramfs*" "e2fsprogs*" lvm2 open-iscsi mdadm \
	unattended-upgrades \
	irqbalance \
	"lxd*" "lxc*" pollinate \
	ufw \
	rsyslog \
	"vim*" \
	"python3*" "libpython3*" \
	"git*" \
	"perl-modules-5.*" \
	"libx11*"

# DEBIAN_FRONTEND=noninteractive for setting default values for questions asked by localpurge install scripts
systemd-nspawn -q -D "$dest" env DEBIAN_FRONTEND=noninteractive apt install -y ncdu localepurge
if ! grep -q "ru_RU.UTF-8" "$dest/etc/locale.nopurge"; then echo "ru_RU.UTF-8" >> "$dest/etc/locale.nopurge"; fi
# now delete unneeded locales from /usr/share/locale/ and /usr/share/man/
sed -i -e 's,^USE_DPKG,#USE_DPKG,g' "$dest/etc/locale.nopurge"
systemd-nspawn -q -D "$dest" localepurge
# restore automatic removel on new packages installations
sed -i -e 's,^#USE_DPKG,USE_DPKG,g' "$dest/etc/locale.nopurge"
# save about 100 MB, can be restored by running apt update
rm -fr "$dest/var/lib/apt/" "$dest/var/cache/apt/"

rm -rf "$rootfs"
echo ""
echo "Ubuntu $CODENAME container was created successfully in ${dest}."
