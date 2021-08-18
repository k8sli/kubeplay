FROM alpine:latest as downloader
ARG SKOPEO_VERSION=v1.4.0
ARG YQ_VERSION=v4.11.2
ARG NERDCTL_VERSION=0.11.0
ARG NGINX_VERSION=1.19
ARG RERGISRRY_VERSION=2.7.1
ARG REDIS_VERSION=6.2
RUN apk --no-cache add wget ca-certificates
WORKDIR /tools
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
    && wget -q -k https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}  -O /tools/yq-linux-${ARCH} \
    && wget -q -k https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-full-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz \
    && wget -q -k https://github.com/k8sli/skopeo/releases/download/v1.4.0/skopeo-linux-${ARCH} -O /tools/skopeo-linux-${ARCH} \
    && chmod a+x /tools/* \
    && ln -s /tools/skopeo-linux-${ARCH} /usr/bin/skopeo

WORKDIR /images/compose
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
    && skopeo copy --insecure-policy --src-tls-verify=false --override-arch ${ARCH} --additional-tag nginx:${NGINX_VERSION} \
       docker://docker.io/library/nginx:${NGINX_VERSION} docker-archive:nginx-${NGINX_VERSION}.tar \
    && skopeo copy --insecure-policy --src-tls-verify=false --override-arch ${ARCH} --additional-tag registry:${RERGISRRY_VERSION} \
       docker://docker.io/library/registry:${RERGISRRY_VERSION} docker-archive:registry-${RERGISRRY_VERSION}.tar \
    && skopeo copy --insecure-policy --src-tls-verify=false --override-arch ${ARCH} --additional-tag bitnami/redis:${REDIS_VERSION} \
       docker://docker.io/bitnami/redis:${REDIS_VERSION} docker-archive:bitnami-redis-${REDIS_VERSION}.tar

FROM scratch as copy
COPY --from=downloader /tools /resources/nginx/tools
COPY --from=downloader /images/compose /images/compose
