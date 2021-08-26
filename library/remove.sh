#!/usr/bin/env bash
remove::remove_cluster(){
  common::run_kubespray "bash /kubespray/run.sh remove-cluster"
  rm -f ${INSTALL_STEPS_FILE}
}

remove::cleanup(){
  # Remove registry domain form /etc/hosts
  sed -i "/${REGISTRY_DOMAIN}/d" /etc/hosts

  # Remove binary tools file
  rm -f ${USR_BIN_PATH}/{yq,helm,kubectl,skopeo}

  # Remove registry domain rootCA crt file from ca trust
  if command -v update-ca-certificates; then
    rm -f /usr/share/ca-certificates/${REGISTRY_DOMAIN}-rootCA.crt
    sed -i "/${REGISTRY_DOMAIN}-rootCA.crt/d" /etc/ca-certificates.conf
    update-ca-certificates >/dev/null
  elif command -v update-ca-trust; then
    rm -f /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN}-rootCA.crt
    update-ca-trust force-enable >/dev/null
  fi
}

remove::uninstall_nerdctl_full(){
  nerdctl compose -f ${COMPOSE_YAML_FILE} down
  nerdctl ps -a -q | xargs -L1 -I {} sh -c "nerdctl stop {}; nerdctl rm -f {}" || true
  systemctl stop containerd buildkit
  systemctl disable containerd buildkit
  find ${RESOURCES_NGINX_DIR}/tools -type f -name 'nerdctl-full*.tar.gz' \
  | xargs -L1 -I {} tar -tf {} \
  | grep -v '/$' \
  | xargs -I {} rm -rf /usr/local/{}
  systemctl daemon-reload
}

remove::remove_compose(){
  remove::uninstall_nerdctl_full
  remove::cleanup
}
