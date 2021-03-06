#!/usr/bin/env bash
#
# Create a base CentOS Docker image.
#
# This script is useful on systems with yum installed (e.g., building
# a CentOS image on CentOS).  See contrib/mkimage-rinse.sh for a way
# to build CentOS images on other systems.

set -e

usage() {
    cat <<EOOPTS
$(basename $0) [OPTIONS] <name>
OPTIONS:
  -p "<packages>"  The list of packages to install in the container.
                   The default is blank.
  -g "<groups>"    The groups of packages to install in the container.
                   The default is "Core".
  -y <yumconf>     The path to the yum config to install packages from. The
                   default is /etc/yum.conf for Centos/RHEL and /etc/dnf/dnf.conf for Fedora
  -t <path>        The path to the target directory where to put rootfs
  -v <version>     Version of ROSA Linux Enterprise Server (73, 75 etc.)
  -a <arch>        Architecture (x86_64, i686)
Example:
  ./rootfs-rels.sh -t /var/lib/machines/rels73 -v 73 rels73
EOOPTS
    exit 1
}

install_groups="basesystem yum rosa-release-server bash which hostname passwd"
while getopts ":y:p:g:v:a:t:h" opt; do
    case $opt in
        y)
            yum_config=$OPTARG
            ;;
        h)
            usage
            ;;
        p)
            install_packages="$OPTARG"
            ;;
        g)
            install_groups="$OPTARG"
            ;;
        v)
            rels_version="$OPTARG"
            ;;
        t)
            target="$OPTARG"
            ;;
        a)
            basearch="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            usage
            ;;
    esac
done
shift $((OPTIND - 1))
name=$1

if [[ -z $name ]]; then
    usage
fi

target="${target:-$(mktemp -d --tmpdir $(basename $0).XXXXXX)}"
rels_version="${rels_version:-73}"
basearch="${basearch:-x86_64}"

if [ ! -d "$target" ]; then mkdir -p "$target"; fi

mkdir -p "$target"/etc/yum.repos.d/
cat > "$target"/etc/yum.repos.d/rels.conf <<EOF
[base]
name=ROSA Enterprise Linux Server - Base
baseurl=http://abf-downloads.rosalinux.ru/rosa-server${rels_version}/repository/$basearch/base/release
enabled=1
gpgcheck=0

[base-updates]
name=ROSA Enterprise Linux Server - Base Updates
baseurl=http://abf-downloads.rosalinux.ru/rosa-server${rels_version}/repository/$basearch/base/updates
enabled=1
gpgcheck=0

[extra]
name=ROSA Enterprise Linux Server - Extra
baseurl=http://abf-downloads.rosalinux.ru/rosa-server${rels_version}/repository/$basearch/extra/release
enabled=1
gpgcheck=0

[extra-updates]
name=ROSA Enterprise Linux Server - Extra Updates
baseurl=http://abf-downloads.rosalinux.ru/rosa-server${rels_version}/repository/$basearch/extra/updates
enabled=1
gpgcheck=0
EOF

yum_config="${yum_config:-"$target/etc/yum.repos.d/rels.conf"}"

set -x

mkdir -m 755 "$target"/dev
mknod -m 600 "$target"/dev/console c 5 1
mknod -m 600 "$target"/dev/initctl p
mknod -m 666 "$target"/dev/full c 1 7
mknod -m 666 "$target"/dev/null c 1 3
mknod -m 666 "$target"/dev/ptmx c 5 2
mknod -m 666 "$target"/dev/random c 1 8
mknod -m 666 "$target"/dev/tty c 5 0
mknod -m 666 "$target"/dev/tty0 c 4 0
mknod -m 666 "$target"/dev/urandom c 1 9
mknod -m 666 "$target"/dev/zero c 1 5

# amazon linux yum will fail without vars set
if [ -d /etc/yum/vars ]; then
	mkdir -p -m 755 "$target"/etc/yum
	cp -a /etc/yum/vars "$target"/etc/yum/
fi

if [[ -n "$install_groups" ]];
then
    yum -c "$yum_config" --installroot="$target" --releasever=/ --setopt=tsflags=nodocs \
        --setopt=group_package_types=mandatory -y install $install_groups
fi

if [[ -n "$install_packages" ]];
then
    yum -c "$yum_config" --installroot="$target" --releasever=/ --setopt=tsflags=nodocs \
        --setopt=group_package_types=mandatory -y install "$install_packages"
fi

yum -c "$yum_config" --installroot="$target" -y clean all

cat > "$target"/etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

# effectively: febootstrap-minimize --keep-zoneinfo --keep-rpmdb --keep-services "$target".
#  locales
rm -rf "$target"/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive}
#  docs and man pages
rm -rf "$target"/usr/share/{man,doc,info,gnome/help}
#  cracklib
rm -rf "$target"/usr/share/cracklib
#  i18n
#rm -rf "$target"/usr/share/i18n
#  yum cache
rm -rf "$target"/var/cache/yum
mkdir -p --mode=0755 "$target"/var/cache/yum
#  sln
rm -rf "$target"/sbin/sln
#  ldconfig
rm -rf "$target"/etc/ld.so.cache "$target"/var/cache/ldconfig
mkdir -p --mode=0755 "$target"/var/cache/ldconfig

echo "nameserver 8.8.8.8" >> "$target"/etc/resolv.conf
# yum fails to bootstrap with systemd at first
systemd-nspawn -D "$target" -q yum install systemd systemd-networkd iproute dhclient -y
systemd-nspawn -D "$target" -q systemctl enable systemd-networkd

# Allow root login into containers
find "$target"/etc/pam.d -type f -exec sed -i '/pam_securetty.so/d' {} \;
# passwd works only after installing systemd,
# otherwise does not find /etc/login.defs, at least in RELS 7.3 (!)
chroot "$target" passwd -d root

version=
for file in "$target"/etc/{redhat,system}-release
do
    if [ -r "$file" ]; then
        version="$(sed 's/^[^0-9\]*\([0-9.]\+\).*$/\1/' "$file")"
        break
    fi
done

if [ -z "$version" ]; then
    echo >&2 "warning: cannot autodetect OS version, using '$name' as tag"
    version=$name
fi

if [ "$DOCKER" = 1 ]; then
    tar --numeric-owner -c -C "$target" . | docker import - $name:latest
    docker run -i -t --rm $name:latest /bin/bash -c 'echo success'
    rm -rf "$target"
    exit
fi

