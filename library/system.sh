#!/usr/bin/env bash

DEFAULT_ARCH=amd64
DEFAULT_URL="http://127.0.0.1:8080"
COMMON_PKGS="curl vim bash-completion rsync ca-certificates chrony wget"

system::centos::disable_selinux(){
  sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
  setenforce 0 || warnlog "Warning: setenforce 0 failed"
  infolog "Disabled selinux service successfully"
}

system::centos::config_repo(){
  infolog "Updated the yum repo file"
  yum clean -q all || true
  cp -f ${RESOURCES_NGINX_DIR}/repos/CentOS-7-All-in-One.repo /etc/yum.repos.d/offline-resources.repo
  sed -i "s#${DEFAULT_URL}#file://${RESOURCES_NGINX_DIR}#g" /etc/yum.repos.d/offline-resources.repo
  if yum makecache -q > /dev/null; then
    infolog "Updated the repo file successfully"
  fi
}

system::debian::config_repo(){
  infolog "Update the apt list file"
  echo "deb [trusted=yes] file://${RESOURCES_NGINX_DIR}/debian/${ARCH} ${VERSION_CODENAME}/" \
        > /etc/apt/sources.list.d/offline-resources.list
  if apt-get update -qq > /dev/null; then
    infolog "Updated the repo file successfully"
  fi
}

system::ubuntu::config_pkgs_repo(){
  infolog "Updated the apt list file"
  echo "deb [trusted=yes] file://${RESOURCES_NGINX_DIR}/ubuntu/${ARCH} ${VERSION_CODENAME}/" \
        > /etc/apt/sources.list.d/offline-resources.list
  if apt-get update -qq > /dev/null; then
    infolog "Updated the repo file successfully"
  fi
}

system::disable_firewalld(){
  if systemctl list-unit-files | grep -q firewalld >/dev/null; then
    infolog "Disable firewalld service"
    systemctl stop firewalld && systemctl disable firewalld
    infolog "Disabled firewalld service successfully"
  fi

  if systemctl list-unit-files | grep -q ufw >/dev/null; then
    infolog "Disable firewalld service"
    systemctl stop ufw && systemctl disable ufw
    infolog "Disabled firewalld service successfully"
  fi
}

system::install_pkgs(){
  if command -v yum > /dev/null; then
    yum install -q -y libseccomp createrepo ${COMMON_PKGS} > /dev/null
  elif command -v apt-get > /dev/null; then
    apt-get install -qq -y libseccomp2 dpkg-dev ${COMMON_PKGS} > /dev/null
  fi
}

system::install_chrony(){
  infolog "Installing chrony as NTP server"
  timedatectl set-ntp true

  CHRONY_CONF_FILE=$(find /etc/chrony* -type f -name 'chrony.conf' | head -n1)
  sed -i '/.*iburst$/d' ${CHRONY_CONF_FILE}
  sed -i "1 i server ${NTP_SERVER} iburst" ${CHRONY_CONF_FILE}

  # Restart chrony daemon, in redhat is chronyd and debian is chrony
  systemctl enable chrony || systemctl enable chronyd
  systemctl restart chrony || systemctl restart chronyd

  if chronyc activity -v | grep -q '^200 OK$' ; then
    infolog "Chrony server is running."
  else
    warnlog "Failed to synchronize time with server: ${NTP_SERVER}"
    exit 1
  fi
}
