#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

REPOSITORY=$1
USER=$2
PASS=$3
DESTDIR=${4:-contents}
SWAP_SIZE=${5:-10g}
WORKING_DIR=${6:-/root/kavesetup}

function setup_repo {
    rm -rf "$WORKING_DIR"
    
    mkdir -p "$WORKING_DIR"
    
    wget -O "$WORKING_DIR/scripts.zip" "$REPOSITORY"

    unzip -d "$WORKING_DIR/temp" "$WORKING_DIR/scripts.zip" 

    mkdir "$WORKING_DIR/$DESTDIR"

    mv "$WORKING_DIR"/temp/*/* "$WORKING_DIR/$DESTDIR"

    rm -rf "$WORKING_DIR"/temp "$WORKING_DIR/scripts.zip"

    AUTOMATION_DIR="$WORKING_DIR/$DESTDIR/automation"
    
    chmod -R +x "$AUTOMATION_DIR/setup"
}

function patch_yum {
    set_archive_repo
    set_v4_only
}

set_archive_repo() {
    #The 6.5 dirs were wiped out the default yum repo just this morning. Therefore we have to use the archive repo.
    local repodir=/etc/yum.repos.d
    rm $repodir/*
    cp "$AUTOMATION_DIR"/patch/CentOS-BaseArchive.repo $repodir
}

set_v4_only() {
    #Not sure why is this but yum tries to use v6 pretty randomly. Last time I failed possibly because of this, let's just force v4.
    echo "ip_resolve=4" >> /etc/yum.conf
}

function install_packages {
    yum install -y epel-release
    yum clean all
    
    yum install -y sshpass pdsh

    yum install -y rpcbind

    yum install -y ipa-server ipa-client
}

function patch_ipa {
    #Patch the installed FreeIPA; as this is a regular yum install Ambari will try to reinstall it but it will not be overwritten of course. The installation of the server on client nodes too must be taken as a precaution - if the user installs the unpatched server afterwards then we can have problems.
    #Why this? In different parts of the code the common name (CN) is build concatenating the DNS domain name and the string "Certificate Authority", and in our case due to Azure long DNSDN the field ends up to be longer than 64 chars which is the RFC-defined standard maximum. This suffix is added as a naming convention, so we cannot just drop it, rather amend it.

    grep -IlR "Certificate Authority" /usr/lib/python2.6/site-packages/ipa* | xargs sed -i 's/Certificate Authority/CA/g'
    #To be fixed in FreeIPA (ideally, but it won't be the case)
    #To be fixed in KAVE (installation will refuse to continue if the total string "FQDN + "Certificate Authority" is longer than 64 OR it gives the option to apply this patch
}

function change_rootpass {
    echo root:$PASS | chpasswd
}

function configure_swap {
    local swapfile=/mnt/resource/swap$SWAP_SIZE

    fallocate -l "$SWAP_SIZE" "$swapfile"

    chmod 600 "$swapfile"

    mkswap "$swapfile"

    swapon "$swapfile"

    echo -e "$swapfile\tnone\tswap\tsw\t0\t0" >> /etc/fstab
}

function disable_iptables {
    #The deploy_from_blueprint KAVE script performs a number of commands on the cluster hosts. Among these, it reads like iptables is stopped, but not permanently. It must be off as otherwise, at least a priori, the FreeIPA clients cannot talk to eachother. We want these changes to be permanent in the (remote) case that the system goes down or is rebooted - otherwise KAVE will stop working afterwards.
    #To be fixed in KAVE
    service iptables stop
    chkconfig iptables off
}

function disable_selinux {
    #Same story as iptables, SELinux must be permanently off but it is only temporary disabled in the blueprint deployment script.
    #To be fixed in KAVE
    echo 0 >/selinux/enforce
    sed -i s/SELINUX=enforcing/SELINUX=disabled/g /etc/selinux/config
}

setup_repo

patch_yum

install_packages

patch_ipa

change_rootpass

configure_swap

disable_iptables

disable_selinux
