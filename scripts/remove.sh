#!/usr/bin/env bash
remove::remove_cluster(){
  common::run_kubespray "bash /kubespray/run.sh remove-cluster"
  rm -f ${INSTALL_STEPS_FILE}
}

remove::clean_hosts(){
  sed "/${REGISTRY_DOMAIN}/d" /etc/hosts
}

remove::uninstall_nerdctl_full(){
  nerdctl compose -f ${COMPOSE_YAML_FILE} down
  nerdctl ps -a -q | xargs nerdctl rm -f
  nerdctl ps -a -q | xargs -L1 -I {} sh -c "nerdctl stop {}; nerdctl rm -f {}"
  find ${RESOURCES_NGINX_DIR}/tools -type f -name 'nerdctl-full*.tar.gz' \
  | xargs -L1 -I {} tar -tf {} \
  | xargs -I {} rm -rf /usr/local/{}
}

remove::remove_compose(){
  remove::uninstall_nerdctl_full
  remove:clean_hosts
}
