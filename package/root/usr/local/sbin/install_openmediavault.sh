#!/bin/bash

if [[ "$(lsb_release -c -s)" != "jessie" ]]; then
	echo "This script only works on Debian/Jessie"
	exit 1
fi

set -xe

# Based on https://github.com/armbian/build/blob/master/scripts/customize-image.sh.template#L31

#Add OMV source.list and Update System
cat > /etc/apt/sources.list.d/openmediavault.list <<- EOF
# deb http://packages.openmediavault.org/public erasmus main
deb https://openmediavault.github.io/packages/ erasmus main
## Uncomment the following line to add software from the proposed repository.
# deb http://packages.openmediavault.org/public erasmus-proposed main
deb https://openmediavault.github.io/packages/ erasmus-proposed main

## This software is not part of OpenMediaVault, but is offered by third-party
## developers as a service to OpenMediaVault users.
# deb http://packages.openmediavault.org/public erasmus partner
EOF

# Add OMV and OMV Plugin developer keys
apt-get update -y
apt-get --yes --force-yes --allow-unauthenticated install openmediavault-keyring
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 7AA630A1EDEE7D73

# install debconf-utils, postfix and OMV
debconf-set-selections <<< "postfix postfix/mailname string openmediavault"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'No configuration'"
apt-get -y install \
    debconf-utils postfix

# install openmediavault
apt-get --yes install openmediavault

# install OMV extras, enable folder2ram, tweak some settings
FILE=$(mktemp)
wget http://omv-extras.org/openmediavault-omvextrasorg_latest_all3.deb -qO $FILE && dpkg -i $FILE && rm $FILE
/usr/sbin/omv-update

# use folder2ram instead of log2ram with OMV
apt-get -y install openmediavault-flashmemory
sed -i -e '/<flashmemory>/,/<\/flashmemory>/ s/<enable>0/<enable>1/' \
    -e '/<ssh>/,/<\/ssh>/ s/<enable>0/<enable>1/' \
    -e '/<ntp>/,/<\/ntp>/ s/<enable>0/<enable>1/' \
	/etc/openmediavault/config.xml

/usr/sbin/omv-mkconf flashmemory
/usr/sbin/omv-mkconf ntp

systemctl disable log2ram
/sbin/folder2ram -enablesystemd

# disable rrdcached
systemctl disable rrdcached

#FIX TFTPD ipv4
[ -f /etc/default/tftpd-hpa ] && sed -i 's/--secure/--secure --ipv4/' /etc/default/tftpd-hpa

. /usr/share/openmediavault/scripts/helper-functions

# improve netatalk performance
apt-get -y install openmediavault-netatalk
AFP_Options="vol dbpath = /var/tmp/netatalk/CNID/%v/"
xmlstarlet ed -L -u "/config/services/afp/extraoptions" -v "$(echo -e "${AFP_Options}")" ${OMV_CONFIG_FILE}

# improve samba performance
SMB_Options="min receivefile size = 16384\nwrite cache size = 524288\ngetwd cache = yes\nsocket options = TCP_NODELAY IPTOS_LOWDELAY"
xmlstarlet ed -L -u "/config/services/smb/extraoptions" -v "$(echo -e "${SMB_Options}")" ${OMV_CONFIG_FILE}

# fix timezone
xmlstarlet ed -L -u "/config/system/time/timezone" -v "UTC" ${OMV_CONFIG_FILE}

# disable monitoring
xmlstarlet ed -L -u "/config/system/monitoring/perfstats/enable" -v "0" ${OMV_CONFIG_FILE}

# update configs
omv-mkconf monit
omv-mkconf netatalk
omv-mkconf samba
omv-mkconf timezone
omv-mkconf collectd

# init OMV
# /usr/sbin/omv-initsystem
