FROM alpine:3.12 as builder
ARG SKOPEO_VERSION=v1.4.0
ARG KUBESPRAY_IMAGE
WORKDIR /images
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
    && apk --no-cache add wget ca-certificates \
    && wget -q -k https://github.com/k8sli/skopeo/releases/download/${SKOPEO_VERSION}/skopeo-linux-${ARCH} -O /usr/local/bin/skopeo \
    && chmod a+x /usr/local/bin/skopeo \
    && skopeo sync --insecure-policy --src-tls-verify=false --dest-tls-verify=false \
              --override-arch ${ARCH} --src docker --dest dir ${KUBESPRAY_IMAGE} kubespray

WORKDIR /kubeplay
COPY . .
RUN cp -rf kubespray/config config/kubespray && rm -rf kubespray
FROM scratch
COPY --from=builder /images /resources/images
COPY --from=builder /kubeplay /
