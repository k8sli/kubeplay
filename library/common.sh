#!/usr/bin/env bash

#
# Set logging colors
#

NORMAL_COL=$(tput sgr0)
RED_COL=$(tput setaf 1)
WHITE_COL=$(tput setaf 7)
GREEN_COL=$(tput setaf 76)
YELLOW_COL=$(tput setaf 202)

debuglog(){ printf "${WHITE_COL}%s${NORMAL_COL}\n" "$@"; }
infolog(){ printf "${GREEN_COL}✔ %s${NORMAL_COL}\n" "$@"; }
warnlog(){ printf "${YELLOW_COL}➜ %s${NORMAL_COL}\n" "$@"; }
errorlog(){ printf "${RED_COL}✖ %s${NORMAL_COL}\n" "$@"; }

common::usage(){
  cat <<EOF
Usage: install.sh [TYPE] [NODE_NAME]
  The script is used for install kubernetes cluster

Parameter:
  [TYPE]\t  this param is used to determine what to do with the kubernetes cluster.
  Available type as follow:
    all              deploy compose addon and kubernetes cluster
    compose          deploy nginx and registry server
    deploy-cluster   install kubernetes cluster
    remove-cluster   remove kubernetes cluster
    add-node         add worker node to kubernetes cluster
    remove-node      remove worker node to kubernetes cluster
    debug            run debug mode for install or troubleshooting

  [NODE_NAME] this param to choose node for kubespray to exceute.
              Note: when [TYPE] is specified [add-node] or [remove-node] this parameter must be set
              multiple nodes are separated by commas, example: node01,node02,node03

EOF
}

# Install containerd-full and binary tools
common::install_tools(){
  infolog "Installing common tools"
  # Install kubectl
  kubectl_file=$(find ${RESOURCES_NGINX_DIR}/files -type f -name "kubectl" | sort -r --version-sort | head -n1)
  cp -f ${kubectl_file} ${USR_BIN_PATH}/kubectl

  # Install helm
  local helm_tar_file=$(find ${RESOURCES_NGINX_DIR}/files -type f -name "helm*-linux-${ARCH}.tar.gz" | sort -r --version-sort | head -n1)
  tar -xf ${helm_tar_file} > /dev/null
  cp -f linux-${ARCH}/helm ${USR_BIN_PATH}/helm
  rm -rf linux-${ARCH}

  # Install skopeo yq mkcert
  cp -f ${RESOURCES_NGINX_DIR}/tools/yq-linux-${ARCH} ${USR_BIN_PATH}/yq
  cp -f ${RESOURCES_NGINX_DIR}/tools/mkcert-linux-${ARCH} ${USR_BIN_PATH}/mkcert
  cp -f ${RESOURCES_NGINX_DIR}/tools/skopeo-linux-${ARCH} ${USR_BIN_PATH}/skopeo
  chmod a+x ${USR_BIN_PATH}/{kubectl,helm,yq,mkcert,skopeo}

  # Install containerd and buildkit
  local nerdctl_tar_file=$(find ${RESOURCES_NGINX_DIR}/tools -type f -name "nerdctl-full-*-linux-${ARCH}.tar.gz" | sort -r --version-sort | head -n1)
  tar -xf ${nerdctl_tar_file} -C /usr/local
  systemctl enable buildkit containerd
  systemctl restart buildkit containerd
  infolog "Common tools installed successfully"
}

common::rudder_config(){
  # Gather variables form config.yaml
  INTERNAL_IP=$(yq eval '.compose.internal_ip' ${CONFIG_FILE})
  if [[ -z ${INTERNAL_IP} ]]; then
    INTERNAL_IP=$(ip r get 1 | sed 's/ uid .*$//' | awk 'NR==1 {print $NF}')
    internal_ip=${INTERNAL_IP} yq eval --inplace '.compose.internal_ip = strenv(internal_ip)' ${CONFIG_FILE}
  fi

  NGINX_HTTP_PORT=$(yq eval '.compose.nginx_http_port' ${CONFIG_FILE})
  REGISTRY_DOMAIN=$(yq eval '.compose.registry_domain' ${CONFIG_FILE})
  NGINX_HTTP_URL="http://${INTERNAL_IP}:${NGINX_HTTP_PORT}"

  IMAGE_REPO=$(yq eval '.default.image_repository' ${CONFIG_FILE})
  GENERATE_DOMAIN_CRT=$(yq eval '.default.generate_domain_crt' ${CONFIG_FILE})
  REGISTRY_HTTPS_PORT=$(yq eval '.default.registry_https_port' ${CONFIG_FILE})
  REGISTRY_PUSH_PORT=$(yq eval '.default.registry_push_port' ${CONFIG_FILE})
  REGISTRY_HTTPS_URL="https://${REGISTRY_DOMAIN}:${REGISTRY_HTTPS_PORT}"
  PUSH_REGISTRY="127.0.0.1:${REGISTRY_PUSH_PORT}"

  OFFLINE_RESOURCES_URL=$(yq -e eval '.default.offline_resources_url' ${CONFIG_FILE})
  if [[ "${OFFLINE_RESOURCES_URL}" == "internal_ip:nginx_http_port" ]]; then
    OFFLINE_RESOURCES_URL=${NGINX_HTTP_URL}
    offline_resources_url=${NGINX_HTTP_URL} yq eval --inplace '.default.offline_resources_url = strenv(offline_resources_url)' ${CONFIG_FILE}
  fi

  NTP_SERVER=$(yq -e eval '.default.ntp_server[0]' ${CONFIG_FILE} 2>/dev/null)
  if [[ ${NTP_SERVER} == "internal_ip" ]]; then
    NTP_SERVER=${INTERNAL_IP}
    ntp_server=${INTERNAL_IP} yq eval --inplace '.default.ntp_server[0] = strenv(ntp_server)' ${CONFIG_FILE}
  fi

  REGISTRY_IP=$(yq -e eval '.default.registry_ip' ${CONFIG_FILE})
  if [[ ${REGISTRY_IP} == "internal_ip" ]]; then
    REGISTRY_IP=${REGISTRY_IP}
    registry_ip=${INTERNAL_IP} yq eval --inplace '.default.registry_ip = strenv(registry_ip)' ${CONFIG_FILE}
  fi

  # Update compose.yaml nginx ports filed
  nginx_http_port="${NGINX_HTTP_PORT}:8080" yq eval --inplace '.services.nginx.ports[0] = strenv(nginx_http_port)' ${COMPOSE_YAML_FILE}
  registry_https_port="${REGISTRY_HTTPS_PORT}:443" yq eval --inplace '.services.nginx.ports[1] = strenv(registry_https_port)' ${COMPOSE_YAML_FILE}
  registry_push_port="${PUSH_REGISTRY}:5000" yq eval --inplace '.services.registry.ports[0] = strenv(registry_push_port)' ${COMPOSE_YAML_FILE}

  # Generate kubespray's env.yaml and inventory file
  yq eval '.default' ${CONFIG_FILE} > ${KUBESPRAY_CONFIG_DIR}/env.yml
  yq eval '.compose' ${CONFIG_FILE} >> ${KUBESPRAY_CONFIG_DIR}/env.yml
  yq eval '.kubespray' ${CONFIG_FILE} >> ${KUBESPRAY_CONFIG_DIR}/env.yml
  yq eval '.inventory' ${CONFIG_FILE} > ${KUBESPRAY_CONFIG_DIR}/inventory
}

# Generate registry domain cert
common::generate_domain_certs(){
  if [[ ${GENERATE_DOMAIN_CRT} == "true" ]]; then
    local DOMAIN=$(echo ${REGISTRY_DOMAIN} | sed 's/[^.]*./*./')
    rm -rf ${CERTS_DIR} ${RESOURCES_NGINX_DIR}/certs
    mkdir -p ${CERTS_DIR} ${RESOURCES_NGINX_DIR}/certs
    infolog "Generating TLS cert for domain: ${REGISTRY_DOMAIN}"
    CAROOT=${CERTS_DIR} mkcert -install
    CAROOT=${CERTS_DIR} mkcert -key-file ${CERTS_DIR}/domain.key -cert-file ${CERTS_DIR}/domain.crt ${REGISTRY_DOMAIN} ${DOMAIN} 

    # Copy domain.crt, domain.key to nginx certs directory
    infolog "Copy certs to ${COMPOSE_CONFIG_DIR}"
    cp -f ${CERTS_DIR}/rootCA.pem ${RESOURCES_NGINX_DIR}/certs/rootCA.crt
  fi
}

# Add registry domain with ip to /etc/hosts file
common::update_hosts(){
  sed -i "/${REGISTRY_DOMAIN}/d" /etc/hosts
  echo "${INTERNAL_IP} ${REGISTRY_DOMAIN}" >> /etc/hosts
}

# Load all docker archive images
common::load_images(){
  infolog "Loading images"
  local IMAGES=$(find ${IMAGES_DIR} -type f -name '*.tar')
  for image in ${IMAGES}; do
    if nerdctl load -i ${image} >/dev/null; then
      infolog "Load ${image} image successfully"
    fi
  done
  : ${KUBESPRAY_IMAGE:=$(nerdctl images | awk '{print $1":"$2}' | grep '^kubespray:*' | sort -r --version-sort | head -n1)}
  kubespray_image="${REGISTRY_DOMAIN}/${IMAGE_REPO}/${KUBESPRAY_IMAGE}" yq eval --inplace '.default.kubespray_image = strenv(kubespray_image)' ${CONFIG_FILE}
  kubespray_image="${REGISTRY_DOMAIN}/${IMAGE_REPO}/${KUBESPRAY_IMAGE}" yq eval --inplace '.kubespray_image = strenv(kubespray_image)' ${KUBESPRAY_CONFIG_DIR}/env.yml
}

common::compose_up(){
  infolog "Starting nginx and registry"
  # Restart nginx and registry
  nerdctl compose -f ${COMPOSE_YAML_FILE} down
  nerdctl compose -f ${COMPOSE_YAML_FILE} up -d

  sleep 5

  # Check registry status
  if nerdctl ps | grep registry | grep Up >/dev/null; then
    infolog "The registry container is running."
  else
    errorlog "Error: The registry container cannot startup!"
    exit 1
  fi

  # Check nginx status
  if nerdctl ps | grep nginx | grep Up >/dev/null; then
    infolog "The nginx container is running."
  else
    errorlog "Error: The nginx container cannot startup!"
    exit 1
  fi
}

common::http_check(){
  status_code=$(curl -k --write-out "%{http_code}" --silent --output /dev/null "${1}")

  if [[ "${status_code}" == "200" ]] ; then
    infolog "The ${1} website is running, and the status code is ${status_code}."
  else
    errorlog "Error: the ${1} website is not running, and the status code is ${status_code}!"
    exit 1
  fi
}

common::health_check(){
  common::http_check ${NGINX_HTTP_URL}/certs/rootCA.crt && common::http_check ${REGISTRY_HTTPS_URL}/v2/_catalog
}

# Run kubespray container
common::run_kubespray(){
  : ${KUBESPRAY_IMAGE:=$(nerdctl images | awk '{print $1":"$2}' | grep '^kubespray:*' | sort -r --version-sort | head -n1)}
  nerdctl rm -f kubespray-runner >/dev/null 2>&1 || true
  nerdctl run --rm -it --net=host --name kubespray-runner \
  -v ${KUBESPRAY_CONFIG_DIR}:/kubespray/config \
  ${KUBESPRAY_IMAGE} $1
}

# Push kubespray image to registry
common::push_kubespray_image(){
  : ${KUBESPRAY_IMAGE:=$(nerdctl images | awk '{print $1":"$2}' | grep '^kubespray:*' | sort -r --version-sort | head -n1)}
  nerdctl tag ${KUBESPRAY_IMAGE} ${PUSH_REGISTRY}/${IMAGE_REPO}/${KUBESPRAY_IMAGE}
  nerdctl push ${PUSH_REGISTRY}/${IMAGE_REPO}/${KUBESPRAY_IMAGE}
}
