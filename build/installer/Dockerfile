ARG KUBESPRAY_IMAGE=ghcr.io/k8sli/kubespray:latest
FROM ${KUBESPRAY_IMAGE} as kubespray
ARG KUBESPRAY_IMAGE
WORKDIR /images
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
    && skopeo sync --insecure-policy --src-tls-verify=false --dest-tls-verify=false \
    --override-arch ${ARCH} --src docker --dest dir ${KUBESPRAY_IMAGE} library

FROM scratch
COPY --from=kubespray /images /images
COPY . .
