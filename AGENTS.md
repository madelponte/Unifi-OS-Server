# AGENTS.md

## Project purpose

This project makes Ubiquiti's UniFi OS Server usable with Docker without installing its host-level Podman service.

Ubiquiti distributes UniFi OS Server as a self-extracting Linux executable. The executable has a ZIP archive appended to it, and that archive contains an OCI/Docker image named `image.tar`. The project downloads the official installer, extracts that image, adds a small Docker compatibility layer, and publishes it to GitHub Container Registry (GHCR).

This repository is unofficial and is not affiliated with or supported by Ubiquiti. Do not commit or redistribute downloaded installer binaries through Git; the resulting container also contains proprietary Ubiquiti software, so preserve the licensing warning in the README.

## Current scope

- Supported installer architecture: Linux x86-64 (`linux/amd64`)
- Published image: `ghcr.io/madelponte/unifi-os-server`
- Published tags:
  - `latest`
  - The version reported by the official installer, such as `5.1.42`
- ARM64 support is a possible future enhancement, but the current workflow and Compose file intentionally target AMD64.

## Important files

- `installer-url.txt` — contains exactly one official x86-64 installer URL. Changing this file on `main` triggers publication.
- `.github/workflows/publish-image.yml` — downloads, extracts, validates, wraps, and publishes the image.
- `Dockerfile` — creates the Docker-compatible image using the image loaded from the installer as its base.
- `docker-entrypoint.sh` — supplies runtime behavior normally handled by Ubiquiti's Podman installer.
- `docker-compose.yml` — generic example intended for the repository and end users.
- `compose.yml` — local, deployment-specific configuration; it is intentionally ignored and must not be committed.
- `README.md` — user-facing publishing, deployment, migration, and port documentation.
- `.gitignore` — excludes local deployment data, extracted archives, and large installers.

## Installer extraction details

The installer is both an ELF executable and a ZIP archive with an executable prefix. Its embedded archive currently contains entries such as:

- `image.tar`
- `mounts.json`
- `portmap.json`
- UniFi helper/service binaries

Use Python's standard `zipfile` module for extraction. It handles the executable prefix cleanly. The `unzip` command can extract the archive but emits an `extra bytes at beginning` warning and may return a non-zero status, which is problematic with `set -e` or `pipefail`.

The workflow intentionally:

1. Accepts only HTTPS x86-64 URLs under `fw-download.ubnt.com/data/unifi-os-server/`.
2. Executes the downloaded installer only with `--version`.
3. Extracts `image.tar` without running the installer.
4. Loads the tar with Docker and verifies that its architecture is `amd64`.
5. Builds the compatibility layer.
6. Pushes both the release version and `latest` tags.

Keep the version tag tied to the value returned by the installer rather than manually parsing the filename.

## Why the compatibility layer exists

The image embedded by Ubiquiti is not completely self-configuring. The official installer normally passes several environment values and generates host-specific state when invoking Podman.

The `Dockerfile` supplies these expected values:

- `container=docker`
- `APP_VERSION`
- `APP_MODEL=UOSSERVER`
- `PRODUCT_NAME=UniFi OS Server`
- `FIRMWARE_PLATFORM=linux-x64`

The wrapper entrypoint:

- Generates a persistent version-5-style `UOS_UUID` on first boot.
- Applies `UOS_SYSTEM_IP` to `/var/lib/unifi/system.properties`.
- Initializes ownership for bind-mounted UniFi, MongoDB, RabbitMQ, and log directories.
- Delegates startup to Ubiquiti's `/root/uos-entrypoint.sh`.

Do not remove the log-directory initialization without testing fresh bind mounts. A fresh bind mount hides directories shipped in the image; without recreating `/var/log/nginx` and `/var/log/mongodb`, those services fail at boot.

## Container runtime requirements

UniFi OS Server runs systemd as PID 1 and starts multiple internal services, including UniFi Network, UniFi Core, nginx, MongoDB, PostgreSQL, and RabbitMQ.

The generic Compose file therefore includes:

- `cgroup: host`
- `/sys/fs/cgroup:/sys/fs/cgroup:rw`
- `NET_ADMIN` and `NET_RAW` capabilities
- Writable tmpfs mounts for `/run`, `/run/lock`, `/tmp`, `/var/lib/journal`, and `/var/opt/unifi/tmp`
- `SIGRTMIN+3` as the stop signal
- A long stop grace period

These settings intentionally trade some container isolation for systemd compatibility. Avoid replacing them with `privileged: true`; the current configuration has been tested successfully without full privilege.

`NET_RAW` is normally already in Docker's default capability set, but it is listed explicitly to match Ubiquiti's expected runtime. `NET_ADMIN` is not a default capability and may be needed for UniFi network-interface behavior.

## Persistence and migration

The generic Compose configuration stores data under `./data` and persists:

- `/persistent`
- `/var/log`
- `/data`
- `/srv`
- `/var/lib/unifi`
- `/var/lib/mongodb`
- `/etc/rabbitmq/ssl`

Do not advise users to copy a LinuxServer UniFi Network `/config` directory directly into these paths. Migration from the legacy Network Application should use a UniFi backup restore or Site Export after stopping the old controller. Both old and new stacks cannot bind the adoption/inform ports simultaneously.

## Networking

The generic Compose file exposes only the web UI and common required ports by default:

- `11443:443/tcp` — UniFi OS web interface
- `8080/tcp` — device communication/inform
- `3478/udp` — STUN and remote-management communication
- `10001/udp` — legacy Network device discovery during adoption
- `10003/udp` — UniFi OS Server discovery

The official installer also installs a host-side `discovery` helper for its rootless Podman networking. The container itself was observed listening on both UDP 10001 and 10003, so Docker publishes both. The helper is not needed for direct Layer 3 adoption through `set-inform` and TCP 8080. If only broadcast discovery fails, investigate host/macvlan networking before assuming another TCP port is missing.

Optional service ports remain commented and documented in `docker-compose.yml`. Keep the generic file free of personal hostnames, absolute user-specific storage paths, external Docker networks, and reverse-proxy labels.

`UOS_SYSTEM_IP` is required and should be the Docker host's LAN IP or a hostname reachable by devices. It controls the inform address written to Network's `system.properties`; allowing it to default to a private Docker bridge address can cause adoption to begin and then stall.

## Validation

At minimum, run these checks after relevant changes:

```bash
bash -n docker-entrypoint.sh
docker compose -f docker-compose.yml config --quiet
git diff --check
```

If an extracted base image is loaded locally, validate the wrapper build:

```bash
docker build \
  --build-arg BASE_IMAGE=uosserver:<embedded-tag> \
  --build-arg APP_VERSION=<installer-version> \
  --build-arg VCS_REF=local-test \
  -t unifi-os-server:test .
```

For meaningful runtime testing, use fresh bind-mounted directories rather than only named volumes. Named volumes copy directory metadata from the image and can conceal initialization bugs that occur with empty bind mounts.

A successful runtime test should confirm:

- The container remains running.
- `systemctl --failed` reports no failed units.
- `unifi-core`, `unifi`, `mongodb`, `postgresql`, `rabbitmq-server`, and `nginx` are active.
- `https://127.0.0.1/` returns HTTP 200 from inside the container.
- `http://127.0.0.1/api/ping` returns HTTP 204.
- `/data/uos_uuid` is non-empty.
- `system_ip` is present when `UOS_SYSTEM_IP` is configured.
- The container stops cleanly with exit code 0.

First boot can take 1–3 minutes and uses roughly 1.5 GiB of memory in the currently tested release. Always remove temporary containers, volumes/directories, and multi-gigabyte test images after testing.

## Change guidelines

- Keep `docker-compose.yml` generic and portable.
- Keep deployment-specific changes in ignored `compose.yml` or another local override.
- Never commit installer executables, `image.tar`, `.env`, or runtime `data/`.
- Preserve versioned tags in addition to `latest` so deployments can pin releases.
- Continue using the built-in `GITHUB_TOKEN` with `packages: write`; do not introduce a personal access token unless necessary.
- Keep workflow inputs out of interpolated shell source; pass values through environment variables and quote them.
- Validate architecture before publishing.
- For future ARM64 support, publish a proper multi-architecture manifest rather than silently replacing the AMD64 `latest` tag.
