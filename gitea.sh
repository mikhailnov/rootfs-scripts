#!/bin/sh
set -xefu
ADD_PPA="${ADD_PPA:-0}"
# From https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
GITEA_VERSION="${GITEA_VERSION:-$(wget -qO- "https://api.github.com/repos/go-gitea/gitea/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")' | awk -F '^v' '{print $NF}')}"
dest="${dest:-$1}"

# First build rootfs tree
# Probably there is nothing Ubuntu-specific,
# so it can be used with any systemd-based GNU/Linux distro
# (except adduser and apt commands)
. ./rootfs-ubuntu.sh
systemd-nspawn -q -D "$dest" \
	apt update
systemd-nspawn -q -D "$dest" \
	apt install -y openssh-server git

# Then setup this rootfs tree
wget https://github.com/go-gitea/gitea/releases/download/v${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH} -O "${dest}/usr/local/bin/gitea"
chmod 755 "${dest}/usr/local/bin/gitea"
wget https://github.com/go-gitea/gitea/raw/master/contrib/systemd/gitea.service -O "${dest}/etc/systemd/system/gitea.service"
mkdir -p "${dest}/etc/gitea/"
wget https://github.com/go-gitea/gitea/raw/master/custom/conf/app.ini.sample -O "${dest}/etc/gitea/app.ini"
sed -i -e 's,DB_TYPE = mysql,DB_TYPE = sqlite3,g' "${dest}/etc/gitea/app.ini"
# Increase session interval from 1 day to 7 days
sed -i -e 's,TIME = 86400,TIME = 604800,g' "${dest}/etc/gitea/app.ini"
sed -i -e 's,PATH = data/gitea.db,PATH = /var/lib/gitea/gitea.db,g' "${dest}/etc/gitea/app.ini"
sed -i -e 's,HTTP_PORT = 3000,HTTP_PORT = 3250,g' "${dest}/etc/gitea/app.ini"

# https://golb.hplar.ch/2018/06/self-hosted-git-server.html
systemd-nspawn -q -D "$dest" \
	adduser --system \
	--shell /bin/bash \
	--gecos 'Gitea user' \
	--group --disabled-password \
	--home /home/git \
	git
mkdir -p "${dest}/var/lib/gitea/"
systemd-nspawn -q -D "$dest" \
	chown -R git:git /var/lib/gitea/
systemd-nspawn -q -D "$dest" \
	chmod 700 -R /var/lib/gitea/
systemd-nspawn -q -D "$dest" \
	chown git:root /etc/gitea/app.ini
systemd-nspawn -q -D "$dest" \
	systemctl enable gitea.service

echo ""
echo "Gitea container (rootfs) has been created in $dest"
