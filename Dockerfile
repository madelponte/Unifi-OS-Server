# BASE_IMAGE is the image loaded from image.tar in the official installer.
ARG BASE_IMAGE=uosserver:embedded
FROM ${BASE_IMAGE}

ARG APP_VERSION
ARG VCS_REF

LABEL org.opencontainers.image.title="UniFi OS Server" \
      org.opencontainers.image.description="UniFi OS Server image extracted from the official Linux installer" \
      org.opencontainers.image.source="https://github.com/madelponte/Unifi-OS-Server" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

# The official installer normally supplies these values to Podman. They are
# part of the runtime configuration rather than the embedded image itself.
ENV container="docker" \
    APP_VERSION="${APP_VERSION}" \
    APP_MODEL="UOSSERVER" \
    PRODUCT_NAME="UniFi OS Server" \
    FIRMWARE_PLATFORM="linux-x64"

STOPSIGNAL SIGRTMIN+3

COPY docker-entrypoint.sh /usr/local/sbin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/sbin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/sbin/docker-entrypoint.sh"]
CMD []
