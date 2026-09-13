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
UOS_SYSTEM_IP=192.168.1.10
TZ=Etc/UTC
```

`UOS_SYSTEM_IP` is required. Use the Docker host's LAN IP or a hostname that resolves to it from the device network—not the container's private bridge address.

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
- `10001/udp` — Network device discovery during adoption
- `10003/udp` — UniFi OS Server discovery

Additional hotspot, Identity Hub, AMQPS, syslog, speed-test, L2 discovery, client-fingerprinting, and support-file ports are documented as commented mappings in `docker-compose.yml`.

### Device adoption troubleshooting

UniFi Network still uses TCP port `8080` for the inform protocol. For same-VLAN automatic discovery, Ubiquiti also documents UDP port `10001`. UniFi OS Server adds UDP port `10003`, so this Compose file publishes both discovery ports.

If a device does not appear automatically—or appears but remains stuck while adopting:

1. Confirm `UOS_SYSTEM_IP` is the Docker host's reachable LAN IP or hostname.
2. Confirm host and inter-VLAN firewalls allow `8080/tcp`, `3478/udp`, `10001/udp`, and `10003/udp`.
3. From the device network, verify that the Docker host is reachable on TCP 8080.
4. For Layer 3 adoption, SSH to the factory-reset device and run:

   ```text
   set-inform http://<UOS_SYSTEM_IP>:8080/inform
   ```

   Ubiquiti notes that the command may need to be run a second time after the device appears in UniFi Network.

The official Linux installer also deploys a host-side discovery helper for its rootless Podman network. It is not involved in direct Layer 3 inform traffic on TCP 8080. Publishing the container's `10001/udp` listener restores the legacy Network discovery path for Docker, but UDP broadcast discovery can still be unreliable across Docker bridges or VLAN boundaries. If manual `set-inform` works while automatic discovery does not, the next step would be a host or macvlan networking option rather than adding more TCP port mappings.
