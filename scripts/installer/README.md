# Jellyfin Nova Installer

The Jellyfin Nova installer provides an interactive installation
workflow for supported Jellyfin environments.

## Components

| File | Purpose |
|---|---|
| `nova-installer.sh` | Interactive Linux shell installer |
| `jellyfin-nova-package.tar.gz` | Bundled Nova distribution package |
| `../docker/nova-init.sh` | Persistent Docker startup integration |

## Installation

Download the development installer:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/topa-LE/jellyfin-nova/main/scripts/installer/nova-installer.sh \
  -o nova-installer.sh
```

Review the script and run:

```bash
sudo bash nova-installer.sh
```

Follow the interactive prompts.

## Docker

Supported LinuxServer Jellyfin deployments can use the Nova
startup hook to restore the installed theme assets when
the container starts.

The Docker configuration must provide the persistent
mounts required by the installation.

## Current Status

- LinuxServer Docker installation tested with Jellyfin 12.2.0.
- Nova assets and Spotlight verified after a container restart.
- Further fresh-installation testing is planned.
- Windows and macOS installation workflows are not yet fully validated.

## License

See the repository's [MIT License](../../LICENSE).

Jellyfin Nova is derived from the open-source
[Abyss for Jellyfin](https://github.com/AumGupta/abyss-jellyfin).
