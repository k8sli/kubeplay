#!/usr/bin/env bash

set +e

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

set -e

# Install containerd-full and binary tools
common::install_tools(){
  infolog "Installing common tools"
  # Install kubectl
  kubectl_file=$(find ${RESOURCES_NGINX_DIR}/files -type f -name "kubectl" | sort -r --version-sort | head -n1)
  cp -f ${kubectl_file} ${USR_BIN_PATH}/kubectl
  chmod +x ${USR_BIN_PATH}/kubectl
  infolog "kubectl installed successfully"

  # Install helm
  local helm_tar_file=$(find ${RESOURCES_NGINX_DIR}/files -type f -name "helm*-linux-${ARCH}.tar.gz" | sort -r --version-sort | head -n1)
  tar -xf ${helm_tar_file} linux-amd64/helm > /dev/null
  cp -f linux-amd64/helm ${USR_BIN_PATH}/helm
  chmod a+x ${USR_BIN_PATH}/helm
  rm -rf linux-amd64
  infolog "helm installed successfully"

  # Install skopeo
  cp -f ${RESOURCES_NGINX_DIR}/tools/skopeo-linux-${ARCH} ${USR_BIN_PATH}/skopeo
  chmod a+x ${USR_BIN_PATH}/skopeo
  infolog "skopeo installed successfully"

  # Install yq
  cp -f ${RESOURCES_NGINX_DIR}/tools/yq-linux-${ARCH} ${USR_BIN_PATH}/yq
  chmod a+x ${USR_BIN_PATH}/yq
  infolog "yq installed successfully"

  # Install containerd and buildkit
  local nerdctl_tar_file=$(find ${RESOURCES_NGINX_DIR}/tools -type f -name "nerdctl-full-*-linux-${ARCH}.tar.gz" | sort -r --version-sort | head -n1)
  tar -xf ${nerdctl_tar_file} -C /usr/local
  systemctl enable buildkit containerd
  systemctl restart buildkit containerd
  infolog "containerd and buildkit installed successfully"
}

common::rudder_config(){
  HTTP_PORT=$(yq eval '.compose.http_port' ${CONFIG_FILE})
  REGISTRY_IP=$(yq eval '.compose.registry_ip' ${CONFIG_FILE})
  REGISTRY_DOMAIN=$(yq eval '.compose.registry_domain' ${CONFIG_FILE})
  REGISTRY_AUTH_USER=$(yq eval '.compose.registry_auth_user' ${CONFIG_FILE})
  REGISTRY_AUTH_PASSWORD=$(yq eval '.compose.registry_auth_password' ${CONFIG_FILE})
  GENERATE_CRT=$(yq eval '.compose.generate_crt' ${CONFIG_FILE})
  HTTP_URL="http://${REGISTRY_IP}:${HTTP_PORT}"
  yq eval '.compose' ${CONFIG_FILE} > ${KUBESPRAY_CONFIG_DIR}/env.yml
  yq eval '.kubespray' ${CONFIG_FILE} >> ${KUBESPRAY_CONFIG_DIR}/env.yml
  echo -e "\noffline_resources_url: ${HTTP_URL}" >> ${KUBESPRAY_CONFIG_DIR}/env.yml
}

common::generate_inventory(){
:
# TDDO
}

# Generate registry domain cert
common::generate_domain_certs(){
  if [[ ${GENERATE_CRT} == "true" ]]; then
    rm -rf ${CERTS_DIR} ${RESOURCES_NGINX_DIR}/certs
    mkdir -p ${CERTS_DIR} ${RESOURCES_NGINX_DIR}/certs
    cp ${CA_CONFIGFILE} ${CERTS_DIR}
    infolog "Generating TLS cert for domain: ${REGISTRY_DOMAIN}"
    # Creating rootCA directory structure
    sed -i "s|CERTS_DIR|${CERTS_DIR}|" ${CERTS_DIR}/rootCA.cnf
    mkdir -p ${CERTS_DIR}/newcerts
    touch ${CERTS_DIR}/index.txt
    echo "unique_subject = no" > ${CERTS_DIR}/index.txt.attr
    echo "01" > ${CERTS_DIR}/serial

    # Generate rootCA.crt along with rootCA.key
    openssl req -config ${CERTS_DIR}/rootCA.cnf \
      -newkey rsa:2048 -nodes -keyout ${CERTS_DIR}/rootCA.key \
      -new -x509 -days 36500 -out ${CERTS_DIR}/rootCA.crt  \
      -subj "/C=CN/ST=BeiJing/L=BeiJing/O=Kubeplay/CN=Kubeplay root CA" >/dev/null 2>&1

    # Generate domain.key
    openssl genrsa -out ${CERTS_DIR}/domain.key 2048 >/dev/null 2>&1

    # Create CSR
    local DOMAIN=$(echo ${REGISTRY_DOMAIN} | sed 's/[^.]*./*./')
    openssl req -new \
      -key ${CERTS_DIR}/domain.key \
      -reqexts SAN \
      -config <(cat ${CERTS_DIR}/rootCA.cnf \
          <(printf "\n[SAN]\nsubjectAltName=DNS:${REGISTRY_DOMAIN},DNS:${DOMAIN}")) \
      -subj "/C=CN/ST=BeiJing/L=BeiJing/O=Kubeplay/CN=${REGISTRY_DOMAIN}" \
      -out ${CERTS_DIR}/domain.csr >/dev/null 2>&1

    # Issue certificate by rootCA.crt and rootCA.key
    openssl ca -config ${CERTS_DIR}/rootCA.cnf -batch -notext \
      -days 36500 -in ${CERTS_DIR}/domain.csr -out ${CERTS_DIR}/domain.crt \
      -cert ${CERTS_DIR}/rootCA.crt -keyfile ${CERTS_DIR}/rootCA.key >/dev/null 2>&1

    # Copy domain.crt, domain.key to nginx certs directory
    infolog "Copy certs to ${COMPOSE_CONFIG_DIR}"
    cp -rf ${CERTS_DIR} ${COMPOSE_CONFIG_DIR}
    cp -f ${CERTS_DIR}/rootCA.crt ${RESOURCES_NGINX_DIR}/certs
  fi

  # Trust the domain rootCA.crt
  if command -v update-ca-certificates; then
    cp -f ${CERTS_DIR}/rootCA.crt /usr/share/ca-certificates/${REGISTRY_DOMAIN}-rootCA.crt
    sed -i "/${REGISTRY_DOMAIN}-rootCA.crt/d" /etc/ca-certificates.conf
    echo ${REGISTRY_DOMAIN}-rootCA.crt >> /etc/ca-certificates.conf
    update-ca-certificates >/dev/null
  elif command -v update-ca-trust; then
    cp {CERTS_DIR}/rootCA.crt /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN}-rootCA.crt
    update-ca-trust force-enable >/dev/null
  fi
}

common::generate_auth_htpasswd(){
  htpasswd -cB -b ${COMPOSE_CONFIG_DIR}/auth.htpasswd ${REGISTRY_AUTH_USER} ${REGISTRY_AUTH_PASSWORD}
}

# Insect registry domain hosts to /etc/hosts file
common::update_hosts(){
  sed -i "/${REGISTRY_DOMAIN}/d" /etc/hosts
  echo "${REGISTRY_IP} ${REGISTRY_DOMAIN}" >> /etc/hosts
}

# Load all docker archive images
common::local_images(){
  local IMAGES=$(find ${IMAGES_DIR} -type f -name '*.tar')
  for image in ${IMAGES}; do
    if nerdctl load -i ${image} >/dev/null; then
      infolog "Load ${image} image successfully"
    fi
  done
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
  common::http_check ${HTTP_URL}/certs/rootCA.crt
  common::http_check https://${REGISTRY_DOMAIN}/v2/_catalog
}

common::run_kubespray(){
  local KUBESPRAY_IMAGE=$(nerdctl images | awk '{print $1":"$2}' | grep '^kubespray:*' | sort -r --version-sort | head -n1)
  nerdctl rm -f kubespray-runner >/dev/null 2>&1 || true
  nerdctl run --rm -it --net=host --name kubespray-runner \
  -v ${KUBESPRAY_CONFIG_DIR}:/kubespray/config \
  ${KUBESPRAY_IMAGE} $1
}

# Push kubespray image to registry
common::push_kubespray_image(){
  nerdctl login "${REGISTRY_DOMAIN}:5000" -u "${REGISTRY_AUTH_USER}" -p "${REGISTRY_AUTH_PASSWORD}"
  local KUBESPRAY_IMAGE=$(nerdctl images | awk '{print $1":"$2}' | grep '^kubespray:*' | sort -r --version-sort | head -n1)
  nerdctl tag ${KUBESPRAY_IMAGE} ${REGISTRY_DOMAIN}/library/${KUBESPRAY_IMAGE}
  nerdctl push ${REGISTRY_DOMAIN}/library/${KUBESPRAY_IMAGE}
}
