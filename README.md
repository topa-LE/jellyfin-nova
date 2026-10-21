<div align="center">

<img src="https://raw.githubusercontent.com/jellyfin/jellyfin-ux/master/branding/SVG/icon-transparent.svg" alt="Jellyfin Logo" width="88" height="88">

# 💜 Jellyfin Nova

### ✨ A modern visual experience for Jellyfin

![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)
![Release](https://img.shields.io/github/v/release/topa-LE/jellyfin-nova?style=for-the-badge)
![Usage](https://img.shields.io/jsdelivr/gh/hm/topa-LE/jellyfin-nova?style=for-the-badge&label=Usage&logo=none)
[![Downloads](https://img.shields.io/github/downloads/topa-LE/jellyfin-nova/total?style=for-the-badge)](https://github.com/topa-LE/jellyfin-nova/releases/latest)

![Themes](https://img.shields.io/badge/Themes-3_Variants-8b5cf6?style=flat-square) ![Spotlight](https://img.shields.io/badge/Spotlight-Integrated-3b82f6?style=flat-square) ![Docker](https://img.shields.io/badge/Docker-Persistent-0ea5e9?style=flat-square) ![Fonts](https://img.shields.io/badge/Fonts-Local-22c55e?style=flat-square)

> **Development Preview** — Jellyfin Nova is under active development.

</div>

---

## 🌌 Overview

**Jellyfin Nova** is a visual customization project for the
[Jellyfin](https://jellyfin.org/) media server.

Nova is based on the open-source Abyss theme and is being developed
as an independent project with its own installation system,
theme distribution and persistent Docker integration.

The project aims to provide a consistent visual experience across
Jellyfin's navigation, media libraries, detail pages and
selected administration areas.

## 🎨 Features

<table width="837" style="width:837px;table-layout:fixed;">
<colgroup>
<col width="261" style="width:261px;">
<col width="576" style="width:576px;">
</colgroup>
<thead>
<tr><th width="261" align="left">Component</th><th width="576" align="left">Description</th></tr>
</thead>
<tbody>
<tr><td width="261">Nova Themes</td><td width="576">Three bundled theme variants with ongoing visual refinements.</td></tr>
<tr><td width="261">Nova Spotlight</td><td width="576">Integrated Spotlight presentation for the Jellyfin interface.</td></tr>
<tr><td width="261">Local Fonts</td><td width="576">Bundled font resources without external CSS font dependencies.</td></tr>
<tr><td width="261">Plugin Styling</td><td width="576">Additional styling for supported Jellyfin plugins.</td></tr>
<tr><td width="261">Docker Installation</td><td width="576">Container-aware installation of Nova web assets.</td></tr>
<tr><td width="261">Docker Persistence</td><td width="576">Automatic restoration of Nova assets on supported container startups.</td></tr>
<tr><td width="261">Installer</td><td width="576">Dedicated Linux shell installer with Docker integration.</td></tr>
</tbody>
</table>

## 🚀 Installation

### 🐧 Linux / Docker

Download the current development installer:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/topa-LE/jellyfin-nova/main/scripts/installer/nova-installer.sh \
  -o nova-installer.sh
```

Review the downloaded script and start the installer:

```bash
sudo bash nova-installer.sh
```

Follow the interactive installer instructions.

> **Important**
>
> Jellyfin Nova is still under development.
> Use a test environment before deploying to production.

### 🐳 Docker Persistence

Supported LinuxServer Jellyfin installations use a persistent
Nova source directory and a container startup hook.

<table width="837" style="width:837px;table-layout:fixed;">
<colgroup>
<col width="261" style="width:261px;">
<col width="576" style="width:576px;">
</colgroup>
<thead>
<tr><th width="261" align="left">Container Path</th><th width="576" align="left">Purpose</th></tr>
</thead>
<tbody>
<tr><td width="261"><code>/config/nova</code></td><td width="576">Persistent Nova theme resources.</td></tr>
<tr><td width="261"><code>/custom-cont-init.d/nova-init.sh</code></td><td width="576">Startup hook restoring the Nova web integration.</td></tr>
<tr><td width="261"><code>/usr/share/jellyfin/web/nova</code></td><td width="576">Active Nova assets served by Jellyfin.</td></tr>
</tbody>
</table>

The required persistent mounts must be configured correctly
for the particular Docker deployment.

The startup hook restores the Nova assets and Spotlight
integration during container startup.

### 💻 Windows and macOS

These environments have not yet completed the same
validation process as the tested Docker setup.

Installation instructions will follow after verification.

## 🔀 Nova vs. Original Abyss

Jellyfin Nova originated from the open-source Abyss project,
but is being developed as a separate distribution.

<table width="837" style="width:837px;table-layout:fixed;">
<colgroup>
<col width="261" style="width:261px;">
<col width="576" style="width:576px;">
</colgroup>
<thead>
<tr><th width="261" align="left">Area</th><th width="576" align="left">Jellyfin Nova</th></tr>
</thead>
<tbody>
<tr><td width="261">Project Identity</td><td width="576">Independent repository, branding and development.</td></tr>
<tr><td width="261">Theme Packaging</td><td width="576">Dedicated Nova package containing CSS, fonts and Spotlight.</td></tr>
<tr><td width="261">Docker Integration</td><td width="576">Container-aware installation and persistent startup integration.</td></tr>
<tr><td width="261">Spotlight</td><td width="576">Nova-specific loader and locally bundled resources.</td></tr>
<tr><td width="261">Theme Variants</td><td width="576">Three variants under independent visual development.</td></tr>
<tr><td width="261">Documentation</td><td width="576">New project-specific documentation and installation guidance.</td></tr>
</tbody>
</table>

This overview describes Nova's development direction.
It is not a complete comparison with every Abyss release.

## 🛠️ Development Status

<table width="837" style="width:837px;table-layout:fixed;">
<colgroup>
<col width="261" style="width:261px;">
<col width="576" style="width:576px;">
</colgroup>
<thead>
<tr><th width="261" align="left">Area</th><th width="576" align="left">Status</th></tr>
</thead>
<tbody>
<tr><td width="261">LinuxServer Docker</td><td width="576">Installation and restart restoration tested with Jellyfin 12.2.0.</td></tr>
<tr><td width="261">Nova CSS</td><td width="576">Successfully installed and served; visual refinements remain.</td></tr>
<tr><td width="261">Spotlight</td><td width="576">Integration tested in the development environment.</td></tr>
<tr><td width="261">Theme Variants</td><td width="576">Three variants available; styling improvements ongoing.</td></tr>
<tr><td width="261">Fresh Installation</td><td width="576">Additional clean-environment validation planned.</td></tr>
<tr><td width="261">Windows / macOS</td><td width="576">Further installer development and validation required.</td></tr>
<tr><td width="261">Documentation</td><td width="576">Being rebuilt for Jellyfin Nova.</td></tr>
</tbody>
</table>

## 🖼️ Screenshots

> **Coming Soon**
>
> Original Jellyfin Nova screenshots will be added
> after the visual design has been finalized.

## 🧭 Roadmap

- Finalize all three Nova theme variants.
- Refine the Jellyfin administration interface.
- Test installation on a fresh Jellyfin environment.
- Complete platform-specific installer verification.
- Replace inherited documentation and preview assets.
- Prepare the first fully documented Nova release.

## 📦 Repository

**GitHub:** https://github.com/topa-LE/jellyfin-nova

Development currently takes place on the `main` branch.

## 📜 License & Acknowledgements

Jellyfin Nova is distributed under the **MIT License**.

See [LICENSE](LICENSE) for the complete license text
and applicable copyright notices.

This project is derived from
[Abyss for Jellyfin](https://github.com/AumGupta/abyss-jellyfin).

The original authors and contributors retain their
respective copyright and attribution rights.

Third-party font licenses are preserved in their
respective source directories.

---

**Made with ❤️ by [topa-LE](https://github.com/topa-LE)** · [MIT License](LICENSE) · [GitHub](https://github.com/topa-LE/jellyfin-nova)
