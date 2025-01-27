#!/bin/bash -xe

echo 'Creating File System Table'
cat <<-EOF > /etc/fstab
/dev/sda1       /boot/efi 	vfat	      noauto,noatime 1 2
/dev/sda2       /boot       ext4        defaults   0 0
/dev/sda3       none        swap        defaults   0 0
/dev/sda4       /           ext4        defaults   0 0

/dev/cdrom      /mnt/cdrom  auto        noauto,ro  0 0
EOF

echo 'Creating Portage Makefile'
cat <<-EOF > /etc/portage/make.conf
CHOST="x86_64-pc-linux-gnu"
CFLAGS="-mtune=generic -O2 -pipe"
CXXFLAGS="\${CFLAGS}"
MAKEOPTS="-j8"
EMERGE_DEFAULT_OPTS="-j8 --with-bdeps=y --quiet-build=y --complete-graph"
FEATURES="\${FEATURES} parallel-fetch"
USE="nls alsa usb unicode openssl"
GRUB_PLATFORMS="emu efi-32 efi-64 pc"
PORTDIR="/usr/portage"
DISTDIR="${PORTDIR}/distfiles"
PKGDIR="${PORTDIR}/packages"
SYMLINK_LIB="no"
EOF

echo 'Configuring Locale'
cat <<-EOF > /etc/env.d/02locale
LANG="en_US.UTF-8"
LC_COLLATE="POSIX"
EOF

cat <<-EOF > /etc/locale.gen
en_US.UTF-8 UTF-8
EOF

echo 'Rebuilding the System Locales'
locale-gen -A -j 16

echo 'Configuring Timezone'
ln -snf /usr/share/zoneinfo/US/Pacific /etc/localtime
echo 'US/Pacific' > /etc/timezone

# This distribution does not like flags described in single files
# all 'package.*', except 'package.keywords', should be directories.
mkdir -p "/etc/portage/package.license"
mkdir -p "/etc/portage/package.use"
mkdir -p "/etc/portage/package.accept_keywords"
mkdir -p "/etc/portage/package.mask"
mkdir -p "/etc/portage/package.unmask"

echo 'Setting Portage Profile'
eselect profile set default/linux/amd64/17.1/no-multilib

echo 'Emerging Dependencies'
# cd /usr/portage
# profile="`grep stable profiles/profiles.desc | grep no-multilib | grep amd64 | awk -F' ' '{print \$2}' | grep -E 'no-multilib\$' | head -1`"
# rm -f /etc/portage/make.profile && ln -s /usr/portage/profiles/$profile /etc/portage/make.profile
emerge sys-kernel/gentoo-kernel-bin sys-boot/grub app-editors/vim app-admin/sudo sys-apps/netplug sys-apps/dmidecode

# If necessary, include the Hyper-V modules in the initramfs and then load them at boot.
if [ "$(dmidecode -s system-manufacturer)" == "Microsoft Corporation" ]; then
  echo 'MODULES_HYPERV="hv_vmbus hv_storvsc hv_balloon hv_netvsc hv_utils"' >> /usr/share/genkernel/arch/x86_64/modules_load
  echo 'modules="hv_storvsc hv_netvsc hv_vmbus hv_utils hv_balloon"' >> /etc/conf.d/modules
  sed -ri "s/(HWOPTS='.*)'/\1 hyperv'/" /usr/share/genkernel/defaults/initrd.defaults
fi

echo 'Configuring Grub'
DEVID=`blkid -s UUID -o value /dev/sda4`
printf "\nGRUB_DEVICE_UUID=\"$DEVID\"\n" >> /etc/default/grub
grub-install --efi-directory=/boot/efi /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

echo 'Configuring Network Services'
emerge sys-apps/ifplugd net-wireless/wireless-tools net-misc/dhcpcd sys-apps/openrc
ln -sf /dev/null /etc/udev/rules.d/80-net-setup-link.rules
ln -sf /dev/null /etc/udev/rules.d/80-net-name-slot.rules
echo 'config_enp0s3=( "dhcp" )' >> /etc/conf.d/net
echo 'config_eth0=( "dhcp" )' >> /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 default

echo 'Configuration SSH'
sed -i -e "s/.*PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
sed -i -e "s/.*PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config
rc-update add sshd default

# Disable the password checks so we can use the default password.
sed -i 's/min=.*/min=1,1,1,1,1/g' /etc/security/passwdqc.conf

echo 'Configuring Users'
echo 'root:locked' | chpasswd
