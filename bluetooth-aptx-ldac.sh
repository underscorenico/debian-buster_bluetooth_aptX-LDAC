#!/bin/bash

# this script compiles the libraries and bluetooth modules to be able to use aptX and LDAC codecs via bluetooth
# on debian buster (10)

####
# 
# Based on the great projects of EHfive (https://github.com/EHfive):
# https://github.com/EHfive/pulseaudio-modules-bt
# https://github.com/EHfive/ldacBT
#
####

## ask user if the backports-repository should be activated to install this has to be done but only if the versin of the system is 'buster' and not already enabled
if [[ "$(lsb_release -cs)" == "buster" ]]  &&  ! apt policy | grep -q buster-backports
then
    read -p "Do you want to enable the backports repository on your system in order to use debian-packages installation ? y/n [n] " backports_enabled  
    
    if [ "$backports_enabled" = "y" ]
    then 
        ## add backports-repository to the source and reload apt cache to able to install the necessary packages
        # add repo-file
        sudo echo -e "# Stable backports\n
        deb https://deb.debian.org/debian buster-backports main contrib non-free\n
        deb-src https://deb.debian.org/debian buster-backports main contrib non-free" > /etc/apt/sources.list.d/buster-backports.list

        # reload package-cache
        sudo apt update
    fi
fi

## installs the packages needed on normal debian buster (10) install
if [ "$backports_enabled" = "y" ]
then 
    sudo apt install bluez-hcidump pkg-config cmake fdkaac libtool libpulse-dev libdbus-1-dev libsbc-dev libbluetooth-dev git
else
    sudo apt install bluez-hcidump pkg-config cmake fdkaac libtool libpulse-dev libdbus-1-dev libsbc-dev libbluetooth-dev git checkinstall
fi



# backup original libraries
echo -e "Backup:\n"
MODDIR=`pkg-config --variable=modlibexecdir libpulse`
sudo find $MODDIR -regex ".*\(bluez5\|bluetooth\).*\.so" -exec cp -v {} {}.bak \;


## creates a temporary directory which is used for the compilation process 
temp_compile_dir=$(mktemp -d)


# jump into that directory
cd "$temp_compile_dir"
## compile libldac
# check out the source from github
git clone https://github.com/EHfive/ldacBT.git
# jump into the dir
cd ldacBT/
# update the git-sumodule
git submodule update --init
# create a direcrtory
mkdir build
# jump in
cd build
# use the c-compiler with the given options
cmake -DCMAKE_INSTALL_PREFIX=/usr -DINSTALL_LIBDIR=/usr/lib -DLDAC_SOFT_FLOAT=OFF ../
# one up
cd ..
# install the compiled thing
if [ "$backports_enabled" = "y" ]
then 
    checkinstall -D --install=yes --pkgname libldac 
else
    sudo make DESTDIR=$DEST_DIR install
fi


## compile pulseaudio-modules-bt - same as above
cd "$temp_compile_dir"

git clone https://github.com/EHfive/pulseaudio-modules-bt.git
cd pulseaudio-modules-bt
git submodule update --init
git -C pa/ checkout v`pkg-config libpulse --modversion|sed 's/[^0-9.]*\([0-9.]*\).*/\1/'`
mkdir build
cd build
cmake ..
make

if [ "$backports_enabled" = "y" ]
then
    checkinstall -D --install=yes --pkgname pulseaudio-module-bluetooth
else
    sudo make install
fi



## configure pulseaudio to use LDAC in high quality - ask user if this has to be done
read -p "Do you want to force using LDAC-codec in high quality? y/n [n] " answer
if [ "$answer" = "y" ]
then 
    # exchange text in the pulseaudio config - in front make a copry name <filename.bak> in same folder
    sudo sed -i.bak 's/^load-module module-bluetooth-discover$/load-module module-bluetooth-discover a2dp_config="ldac_eqmid=hq ldac_fmt=f32"/g' /etc/pulse/default.pa
fi
 

# restart pulseaudio and bluetooth service
pulseaudio -k
sudo systemctl restart bluetooth.service


# User messages and infos
echo ''
echo '#################################'
echo '#################################'
echo -E "To test which codec is used for your device, disconnect your device, start this command: sudo hcidump | grep -A 10 -B 10 'Set config', then reconnect your device."
echo -E "Check the line with 'Media Codec - non-A2DP (xyz)' below 'Set config'"
echo -E "To configure the codec manually check the options for /etc/pulse/default.pa here: https://github.com/EHfive/pulseaudio-modules-bt#configure"


sudo rm -R "$temp_compile_dir"
