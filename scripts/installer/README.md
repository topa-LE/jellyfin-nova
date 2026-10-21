# Jellyfin Nova – Nova Installer

Eigenstaendige Installationswerkzeuge fuer das Repository
topa-LE/jellyfin-nova.

## Verbindliche Bezeichnungen

- Installer-Verzeichnis: scripts/installer/
- Linux/macOS: nova-installer.sh
- Windows: nova-installer.ps1
- Docker: nova-installer-docker.sh
- Installationsverzeichnis in Jellyfin: nova/
- CSS-Einstiegspunkt: nova.css
- Spotlight-Kennungen: nova-spotlight
- CSS-Verwaltungsblock: NOVA THEME START / NOVA THEME END

## Paketquelle

Das Nova-Paket wird durch scripts/build-nova.mjs erzeugt.

Der Inhalt von dist/ wird spaeter unter nova/ im
Jellyfin-Webverzeichnis bereitgestellt:

    nova/
    ├── nova.css
    ├── fonts/
    ├── plugins/
    └── spotlight/
        ├── spotlight-loader.js
        ├── spotlight.html
        └── spotlight.css

## Installationsregeln

- Ausschliesslich Nova-Dateien installieren und verwalten.
- Bestehende fremde Custom-CSS-Eintraege erhalten.
- Keine automatische Entfernung alter Abyss-Installationen.
- Installation und Deinstallation wiederholbar gestalten.
- Vor Aenderungen bestehende Dateien sichern.
- Relative CSS-, Spotlight- und Schriftpfade erhalten.
- Keine externen Schrift-CDNs.
- Keine produktiven Jellyfin-Server ohne Freigabe veraendern.
- Linux/macOS, Windows und Docker getrennt testen.
- Keine Commits oder Pushes ohne ausdrueckliche Freigabe.

## Geplante Implementierung

1. Lokale Paketbereitstellung und Validierung.
2. Nova Installer fuer Linux/macOS.
3. Nova Installer fuer Windows.
4. Nova Installer fuer Docker.
5. Sichere Installation und Deinstallation.
6. Automatische Integrationstests.

Die tatsaechliche CSS-URL wird erst bei der Implementierung
anhand des Jellyfin-Webpfads festgelegt und getestet.
