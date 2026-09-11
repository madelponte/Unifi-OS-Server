# UniFi OS Server for Docker

This repository publishes the container embedded in Ubiquiti's official x86-64 UniFi OS Server installer as:

```text
ghcr.io/madelponte/unifi-os-server:latest
ghcr.io/madelponte/unifi-os-server:<installer-version>
```

The project is unofficial and is not affiliated with or supported by Ubiquiti. The image contains Ubiquiti software; review its license and terms before redistributing it.

## Publishing a new version

1. Copy the current **Linux x86-64** installer URL from Ubiquiti.
2. Replace the single URL in [`installer-url.txt`](installer-url.txt).
3. Commit and push the change to `main`.

[`.github/workflows/publish-image.yml`](.github/workflows/publish-image.yml) then:

1. Downloads the installer directly from `fw-download.ubnt.com`.
2. Reads the installer version.
3. Extracts its embedded `image.tar` without running the installer.
4. Verifies that the loaded image is `linux/amd64`.
5. Adds the small amount of runtime configuration normally supplied by the Podman installer.
6. Publishes both versioned and `latest` tags to this repository's GHCR package.

The workflow can also be run manually from the Actions page. Its optional URL input overrides `installer-url.txt` for that run.

The workflow uses the built-in `GITHUB_TOKEN`; no registry secret is required. If consumers cannot pull the resulting package anonymously, change the package visibility to **Public** in the repository/package settings or authenticate with `docker login ghcr.io`.

## Running with Docker Compose

[`docker-compose.yml`](docker-compose.yml) is a generic standalone configuration. It stores persistent data below `./data`, publishes the web interface on port `11443`, and does not require an external database or reverse proxy.

Create an `.env` file with the hostname or LAN IP that adopted devices can reach:

```dotenv
UOS_SYSTEM_IP=192.0.2.10
TZ=Etc/UTC
```

Create the storage directories and start the server:

```bash
mkdir -p data/{persistent,var-log,data,srv,var-lib-unifi,var-lib-mongodb,etc-rabbitmq-ssl}
docker compose pull
docker compose up -d
docker compose logs -f unifi-os-server
```

Open `https://HOST:11443` to complete setup. The certificate is self-signed until one is configured in UniFi OS, so a browser warning on first access is expected.

The image runs systemd internally, so the cgroup mount, host cgroup namespace, capabilities, and tmpfs mounts in `docker-compose.yml` are intentional. The first boot can take several minutes. This Compose file currently targets `linux/amd64`.

### Migration from the legacy Network Application

Do not copy the old LinuxServer `/config` directory into the new volumes. Before replacing the old stack, create/download a Network Application backup or use Site Export. Stop the old application, start UniFi OS Server, and restore/import through its setup UI. In particular, both stacks cannot bind the adoption and inform ports at the same time.

Back up the complete `./data` directory to preserve the UniFi OS Server installation.

## Exposed ports

The generic Compose file enables:

- `11443/tcp` — UniFi OS web interface (mapped to container port `443`)
- `8080/tcp` — device/application communication and inform
- `3478/udp` — STUN and remote-management communication
- `10003/udp` — discovery

Additional hotspot, Identity Hub, AMQPS, syslog, speed-test, and support-file ports are documented as commented mappings in `docker-compose.yml`.
