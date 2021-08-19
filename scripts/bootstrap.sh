#!/usr/bin/env bash

bootstrap::centos(){
  system::centos::disable_firewalld
  system::centos::disable_selinux
  system::centos::config_repo
  system::centos::install_packages
}

bootstrap::debian(){
  system::debian::disable_firewalld
  system::debian::config_repo
  system::debian::install_packages
}

bootstrap::ubuntu(){
  system::ubuntu::disable_ufw
  system::ubuntu::config_repo
  system::ubuntu::install_packages
}

bootstrap(){
  case ${ID} in
    Debian|debian)
      bootstrap::debian
      ;;
    CentOS|centos)
      bootstrap::centos
      ;;
    Ubuntu|ubuntu)
      bootstrap::ubuntu
      ;;
    *)
      warnlog "Not support system: ${ID}"
      usage
      ;;
  esac
  common::install_tools
  common::rudder_config
  common::update_hosts
  common::generate_domain_certs
  common::generate_auth_htpasswd
  common::local_images
  common::compose_up
  common::health_check
}
