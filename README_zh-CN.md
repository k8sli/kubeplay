## 简介

[kubeplay](https://github.com/k8sli/kubeplay) 是基于 [kubespray](https://github.com/k8sli/kubespray) 实现的离线部署 kuberneres 集群的工具

### 特性

- 包含所有依赖，一条命令即可完成离线安装
- 支持 amd64 和 arm64 CPU 架构
- kubeadm 生成的证书有效期调整为 10 年
- 去 docker 化部署，无缝迁移至 containerd 作为容器运行时
- 适用于 toB 私有化场景，可离线安装平台所依赖的 rpm/deb 包（如存储客户端）
- 多集群部署，支持在 kubernetes 集群中以 Job Pod 方式部署 kubernetes 集群
- 使用 GitHub Actions 构建离线安装包，无需充值会员，100% 开源 100% 免费

### 组件版本

| addon        | version        | 用途                        |
| ------------ | -------------- | --------------------------- |
| kubernetes   | v1.21.4        | kubernetes                  |
| containerd   | v1.4.6         | 容器运行时                  |
| etcd         | v3.4.13        | etcd 服务                   |
| crictl       | v1.21.0        | CRI CLI 工具                |
| pause        | 3.3            | pause 容器镜像              |
| cni-plugins  | v0.9.1         | CNI 插件                    |
| calico       | v3.18.5        | calico                      |
| autoscaler   | 1.8.3          | DNS 自动扩缩容              |
| coredns      | v1.8.0         | 集群 DNS 服务               |
| flannel      | v0.14.0        | flannel                     |
| nginx        | 1.19           | node 节点反向代理 APIserver |
| canal        | calico/flannel | 集成 calico 和 flannel      |
| helm         | v3.6.3         | helm CLI 工具               |
| nerdctl      | 0.8.0          | containerd CLI 工具         |
| nerdctl-full | 0.11.0         | containerd 工具全家桶       |
| registry     | v2.7.1         | 提供镜像下载服务            |
| skopeo       | v1.4.0         | 镜像搬运工具                |

### 支持的 Linux 发行版

| distribution | version     | arch        |
| ------------ | ----------- | ----------- |
| CentOS       | 7/8         | amd64/arm64 |
| Debian       | 9/10        | amd64/arm64 |
| Ubuntu       | 18.04/20.04 | amd64/arm64 |
| Fedora       | 33/34       | amd64/arm64 |

### compose

在部署工具运行节点使用 [nerdctl compose](https://github.com/containerd/nerdctl) 启动 nginx 和 registry 容器，分别提供离线资源下载和镜像分发服务。

### kubespray

使用 kubernetes 社区的 [kubespray](https://github.com/kubernetes-sigs/kubespray) 作为集群部署的功能，部署过程中所依赖的资源从 compose 节点获取。

## 部署

### 下载

在 GitHub 的 release 页面 [k8sli/kubeplay/releases](https://github.com/k8sli/kubeplay/releases)，根据部署机器的 Linux 发行版和 CPU 架构选择相应的安装包，将它下载到部署节点。

```bash
kubeplay-v0.1.0-alpha.3-centos-7.sha256sum.txt # 安装包 sha256sum 校验文件
kubeplay-v0.1.0-alpha.3-centos-7-amd64.tar.gz  # 适用于 CentOS 7 amd64 机器
kubeplay-v0.1.0-alpha.3-centos-7-amd64.tar.gz  # 适用于 CentOS 7 arm64 机器
```

### 配置

```bash
$ tar -xpf kubeplay-x.y.z-xxx-xxx.tar.gz
$ cd kubeplay
$ cp config-sample.yaml config.yaml
$ vi config.yaml
```

`config.yaml` 配置文件主要分为如下几个部分

- compose：nginx 和 registry 部署节点信息
- kubespray：kubespray 部署配置
- invenory：kubernetes 集群节点 ssh 登录信息
- default：一些默认的参数

#### compose

| 参数            | 说明                             | 示例                |
| --------------- | -------------------------------- | ------------------- |
| internal_ip     | 部署节点内网访问 IP              | 192.168.10.11       |
| nginx_http_port | 部署 nginx 服务暴露的端口        | 8080                |
| registry_domain | 部署 registry 镜像仓库服务的域名 | kube.registry.local |

```yaml
compose:
  # Compose bootstrap node ip, default is local internal ip
  internal_ip: 172.20.0.25
  # Nginx http server bind port for download files and packages
  nginx_http_port: 8080
  # Registry domain for CRI runtime download images
  registry_domain: kube.registry.local
```

#### kubespray

| 参数                         | 说明                     | 示例           |
| ---------------------------- | ------------------------ | -------------- |
| kube_version                 | kubernetes 版本号        | v1.21.3        |
| external_apiserver_access_ip | 集群APIserver外部访问 IP | 192.168.10.100 |
| kube_network_plugin          | 选用 CNI 网络插件名称    | calico         |
| container_manager            | 容器运行时               | containerd     |
| etcd_deployment_type         | etcd 部署方式            | host           |

```yaml
kubespray:
  # Kubernetes version by default, only support v1.20.6
  kube_version: v1.21.3
  # For deploy HA cluster you must configure a external apiserver access ip
  external_apiserver_access_ip: 127.0.0.1
  # Set network plugin to calico with vxlan mode by default
  kube_network_plugin: calico
  #Container runtime, only support containerd if offline deploy
  container_manager: containerd
  # Now only support host if use containerd as CRI runtime
  etcd_deployment_type: host
  # Settings for etcd event server
  etcd_events_cluster_setup: true
  etcd_events_cluster_enabled: true
```

#### inventory

inventory 为 kubernetes 集群节点的 ssh 登录配置，支持 yaml, json, ini 三种格式。

| 参数                         | 说明                      | 示例                             |
| ---------------------------- | ------------------------- | -------------------------------- |
| ansible_port                 | 主机 ssh 登录端口号       | 22                               |
| ansible_user                 | 主机 ssh 登录用户名       | root                             |
| ansible_ssh_pass             | 主机 ssh 登录密码         | password                         |
| ansible_ssh_private_key_file | 如果使用 private key 登录 | 必须为`/kubespray/config/id_rsa` |
| ansible_host                 | 节点 IP                   | 172.20.0.21                      |

- yaml 格式

```yaml
# Cluster nodes inventory info
inventory:
  all:
    vars:
      ansible_port: 22
      ansible_user: root
      ansible_ssh_pass: Password
      # ansible_ssh_private_key_file: /kubespray/config/id_rsa
    hosts:
      node1:
        ansible_host: 172.20.0.21
      node2:
        ansible_host: 172.20.0.22
      node3:
        ansible_host: 172.20.0.23
      node4:
        ansible_host: 172.20.0.24
    children:
      kube_control_plane:
        hosts:
          node1:
          node2:
          node3:
      kube_node:
        hosts:
          node1:
          node2:
          node3:
          node4:
      etcd:
        hosts:
          node1:
          node2:
          node3:
      k8s_cluster:
        children:
          kube_control_plane:
          kube_node:
      gpu:
        hosts: {}
      calico_rr:
        hosts: {}
```

- json 格式

```json
inventory: |
  {
    "all": {
      "vars": {
        "ansible_port": 22,
        "ansible_user": "root",
        "ansible_ssh_pass": "Password"
      },
      "hosts": {
        "node1": {
          "ansible_host": "172.20.0.21"
        },
        "node2": {
          "ansible_host": "172.20.0.22"
        },
        "node3": {
          "ansible_host": "172.20.0.23"
        },
        "node4": {
          "ansible_host": "172.20.0.24"
        }
      },
      "children": {
        "kube_control_plane": {
          "hosts": {
            "node1": null,
            "node2": null,
            "node3": null
          }
        },
        "kube_node": {
          "hosts": {
            "node1": null,
            "node2": null,
            "node3": null,
            "node4": null
          }
        },
        "etcd": {
          "hosts": {
            "node1": null,
            "node2": null,
            "node3": null
          }
        },
        "k8s_cluster": {
          "children": {
            "kube_control_plane": null,
            "kube_node": null
          }
        },
        "gpu": {
          "hosts": {}
        },
        "calico_rr": {
          "hosts": {}
        }
      }
    }
  }
```

- ini 格式

```ini
inventory: |
  [all:vars]
  ansible_port=22
  ansible_user=root
  ansible_ssh_pass=Password
  #ansible_ssh_private_key_file=/kubespray/config/id_rsa

  [all]
  kube-control-01 ansible_host=172.20.0.21
  kube-control-02 ansible_host=172.20.0.23
  kube-control-03 ansible_host=172.20.0.22
  kube-node-01 ansible_host=172.20.0.24

  [bastion]
  # bastion-01 ansible_host=x.x.x.x ansible_user=some_user

  [kube_control_plane]
  kube-control-01
  kube-control-02
  kube-control-03

  [etcd]
  kube-control-01
  kube-control-02
  kube-control-03


  [kube_node]
  kube-control-01
  kube-control-02
  kube-control-03
  kube-node-01

  [calico_rr]

  [k8s_cluster:children]
  kube_control_plane
  kube_node
  calico_rr
```

#### default

以下几个默认的参数在没有特殊要求的情况下不建议修改，直接保持默认即可。`ntp_server` 参数为默认值时会自动替换成 compose 中的 `internal_ip` 值；`registry_ip` 和 `offline_resources_url` 这两个参数会根据 compose 中的参数自动生成无需修改。

| 参数                          | 说明                                     |  示例   |
| ----------------------------- | ---------------------------------------- | :-----: |
| ntp_server                    | ntp 时钟同步服务器域名或 IP              |    -    |
| registry_ip                   | 镜像仓库节点 IP                          |    -    |
| offline_resources_url         | 提供离线资源下载的 URL 地址              |    -    |
| offline_resources_enabled     | 是否为离线部署                           |  true   |
| generate_domain_crt           | 是否为镜像仓库域名生成自签证书           |  true   |
| image_repository              | 镜像仓库的 repo 或 project               | library |
| registry_https_port           | 镜像仓库的端口号，该端口已禁止 PUSH 镜像 |   443   |
| registry_push_port            | 用于 PUSH 镜像的 registry 端口号         |  5000   |
| download_container            | 是否在所有节点 pull 下所有组件的镜像     |  false  |
| cilium_enable_hubble          | cilium 中是否开启 hubble                 |  false  |
| cilium_hubble_install         | 是否安装 cilium hubble-ui                |  false  |
| cilium_hubble_tls_generate    | hubble 是否生成 tls 证书                 |  false  |
| cilium_kube_proxy_replacement | 使用 cilium 代替 kube-proxy 的策略       |  probe  |

```yaml
default:
  # NTP server ip address or domain, default is internal_ip
  ntp_server:
    - internal_ip
  # Registry ip address, default is internal_ip
  registry_ip: internal_ip
  # Offline resource url for download files, default is internal_ip:nginx_http_port
  offline_resources_url: internal_ip:nginx_http_port
  # Use nginx and registry provide all offline resources
  offline_resources_enabled: true
  # Image repo in registry
  image_repository: library
  # Kubespray container image for deploy user cluster or scale
  kubespray_image: "kubespray"
  # Auto generate self-signed certificate for registry domain
  generate_domain_crt: true
  # For nodes pull image, use 443 as default
  registry_https_port: 443
  # For push image to this registry, use 5000 as default, and only bind at 127.0.0.1
  registry_push_port: 5000
  # Set false to disable download all container images on all nodes
  download_container: false
  # enable support hubble in cilium
  cilium_enable_hubble: false
  # install hubble-relay, hubble-ui
  cilium_hubble_install: false
  # install hubble-certgen and generate certificates
  cilium_hubble_tls_generate: false
  # Kube Proxy Replacement mode (strict/probe/partial)
  cilium_kube_proxy_replacement: probe
```

### 部署集群

```bash
$ bash install.sh
```

### 增加节点

```bash
$ bash install.sh add-node $NODE_NAMES
```

### 删除节点

```bash
$ bash install.sh remove-node $NODE_NAME
```

### 移除集群

```bash
$ bash install.sh remove-cluster
```

### 移除所有组件

```bash
$ bash install.sh remove
```
