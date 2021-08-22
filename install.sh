#!/usr/bin/env bash
INSTALL_TYPE=$1
: ${INSTALL_TYPE:=all}

# Common utilities, variables and checks for all build scripts.
set -o errexit
set -o nounset
set -o pipefail

# Gather variables about bootstrap system
USR_BIN_PATH=/usr/local/bin
export PATH="${PATH}:${USR_BIN_PATH}"
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Define glob vars
KUBE_ROOT="$(cd "$(dirname "$0")" && pwd)"
CERTS_DIR="${KUBE_ROOT}/config/certs"
CONFIG_FILE="${KUBE_ROOT}/config.yaml"
CA_CONFIGFILE="${KUBE_ROOT}/config/rootCA.cnf"
COMPOSE_YAML_FILE="${KUBE_ROOT}/compose.yaml"
IMAGES_DIR="${KUBE_ROOT}/resources/images"
COMPOSE_CONFIG_DIR="${KUBE_ROOT}/config/compose"
OUTPUT_ENV_FILE="${KUBE_ROOT}/.install-env.sh"
RESOURCES_NGINX_DIR="${KUBE_ROOT}/resources/nginx"
KUBESPRAY_CONFIG_DIR="${KUBE_ROOT}/config/kubespray"
INSTALL_STEPS_FILE="${KUBESPRAY_CONFIG_DIR}/.install_steps"

# Import all functions from scripts/*.sh
for file in ${KUBE_ROOT}/scripts/*.sh; do source ${file}; done

# Get os release info
if ! source /etc/os-release; then
  errorlog "Every system that we officially support has /etc/os-release"
  exit 1
fi

if [ ! -f ${CONFIG_FILE} ]; then
  errorlog "The ${CONFIG_FILE} file is not existing"
  exit 1
fi

usage(){
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
  exit 0
}

deploy_cluster(){
  common::rudder_config
  common::push_kubespray_image
  common::run_kubespray "bash /kubespray/run.sh deploy-cluster"
}

add_nodes(){
  common::run_kubespray "bash /kubespray/run.sh add-node $2"
}

remove_nodes(){
  common::run_kubespray "bash /kubespray/run.sh remove-node $2"
}

kubespray_debug(){
  common::run_kubespray "bash"
}

install_all(){
  bootstrap
  deploy_cluster
}

main(){
  case ${INSTALL_TYPE} in
    all)
      install_all
      ;;
    compose)
      bootstrap
      ;;
    cluster)
      deploy_cluster
      ;;
    remove)
      common::rudder_config
      remove::remove_cluster
      remove::remove_compose
      ;;
    remove-cluster)
      common::rudder_config
      remove::remove_cluster
      ;;
    remove-compose)
      common::rudder_config
      remove::remove_compose
      ;;
    add-nodes)
      ;;
    remove-node)
      ;;
    health-check)
      common::health_check
      ;;
    debug)
      kubespray_debug
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echowarn "unknow [TYPE] parameter: ${INSTALL_TYPE}"
      usage
      ;;
  esac
}

main "$@"
