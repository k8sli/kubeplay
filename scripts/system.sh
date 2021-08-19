#!/usr/bin/env bash

DEFAULT_ARCH=amd64
DEFAULT_URL="http://127.0.0.1:8080"
COMMON_PKGS="curl vim net-tools bash-completion rsync ca-certificates chrony wget"

# Install mutiple rpm packages
system::yum_install(){
  if ! yum -q -y install "$@" >/dev/null; then
    errorlog "  Error: yum install failed on $(hostname):"
    exit 1
  fi
  infolog "$* package install completed successfully"
}

# Install mutiple deb packages
system::apt_install(){
  if ! apt-get install -q -y "$@" >/dev/null; then
    errorlog " Error: apt install failed on $(hostname):"
    errorlog "   sudo apt-get -q -y install $*"
    exit 1
  fi
  infolog "$* package install completed successfully"
}

system::centos::disable_firewalld_selinux(){
  if systemctl list-unit-files | grep firewalld >/dev/null; then
    warnlog "Disable firewalld service and selinux"
    systemctl stop firewalld && systemctl disable firewalld
    infolog "Disabled firewalld service successfully"
  fi
}

system::centos::disable_selinux(){
  sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
  setenforce 0 || warnlog "Warning: setenforce 0 failed"
  infolog "Disabled selinux service successfully"
}

system::centos::config_repo(){
  infolog "Updated the yum repo file"
  yum clean -q all || true
  cp ${RESOURCES_NGINX_DIR}/repos/CentOS-7-All-in-One.repo /etc/yum.repos.d/CentOS-7-All-in-One.repo
  sed -i "s#${DEFAULT_URL}#file://${RESOURCES_NGINX_DIR}#g" /etc/yum.repos.d/CentOS-7-All-in-One.repo
  sed -i "s#${DEFAULT_ARCH}#${ARCH}#g" /etc/yum.repos.d/CentOS-7-All-in-One.repo
  if yum makecache -q > /dev/null; then
    infolog "Updated the repo file successfully"
  fi
}

system::centos::install_packages(){
  yum_install libseccomp createrepo httpd-tools ${COMMON_PKGS}
}

system::debian::disable_firewalld(){
  if systemctl list-unit-files | grep firewalld >/dev/null; then
    infolog "Disable firewalld service"
    systemctl stop firewalld && systemctl disable firewalld
    infolog "Disabled firewalld service successfully"
  fi
}

system::debian::config_repo(){
  infolog "Update the apt list file"
  echo "deb [trusted=yes] file://${RESOURCES_NGINX_DIR}/debian/${ARCH} ${VERSION_CODENAME}/" \
        > /etc/apt/sources.list.d/Debian-${VERSION_CODENAME}-All-in-One.list
  if apt-get update -qq > /dev/null; then
    infolog "Updated the repo file successfully"
  fi
}

system::debian::install_packages(){
  system::apt_install libseccomp2 dpkg-dev apache2-utils ${COMMON_PKGS}
}

system::ubuntu::disable_ufw(){
  if systemctl list-unit-files | grep ufw >/dev/null; then
    infolog "Disable firewalld service"
    systemctl stop ufw && systemctl disable ufw
    infolog "Disabled firewalld service successfully"
  fi
}

system::ubuntu::config_repo(){
  infolog "Updated the apt list file"
  echo "deb [trusted=yes] file://${RESOURCES_NGINX_DIR}/ubuntu/${ARCH} ${VERSION_CODENAME}/" \
        > /etc/apt/sources.list.d/Ubuntu-${VERSION_CODENAME}-All-in-One.list
  if apt-get update -qq > /dev/null; then
    infolog "Updated the repo file successfully"
  fi
}

system::ubuntu::install_packages(){
  system::apt_install libseccomp2 dpkg-dev apache2-utils ${COMMON_PKGS}
}
