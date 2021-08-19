#!/usr/bin/env bash
remove:remove_kubernetes(){
  run_kubespray "bash /kubespray/run.sh remove-cluster"
}

remove:clean_hosts(){
  sed "/${REGISTRY_DOMAIN}/d" /etc/hosts
}

remove::nerdctl_full(){
  nerdctl compose -f ${COMPOSE_YAML_FILE} down
  nerdctl ps -a -q | xargs -L1 -I {} sh -c "nerdctl stop {}; nerdctl rm -f {}"
  find ${RESOURCES_NGINX_DIR}/tools -type f -name 'nerdctl-full*.tar.gz' \
  | xargs -L1 -I {} tar -tf {} \
  | xargs -I {} rm -rf /usr/local/{}
}
