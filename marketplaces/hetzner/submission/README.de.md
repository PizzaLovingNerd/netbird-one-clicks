# Hetzner Cloud NetBird

NetBird ist eine Open-Source-Plattform für sichere, WireGuard-basierte private
Netzwerke. Dieses Image enthält die Abhängigkeiten und das Release-Paket für
eine selbst gehostete NetBird-Control-Plane mit Dashboard, integriertem
Identity Provider, Relay und automatischem HTTPS.

## Erste Schritte

Erstellen Sie aus dem NetBird-Snapshot einen Ubuntu-24.04-Server mit SSH-Key
und mindestens 2 GB RAM. Richten Sie einen öffentlichen Hostnamen auf die
IPv4-Adresse des Servers. Verwenden Sie die mit `render-user-data.sh` erzeugten
Cloud-Init-Daten oder melden Sie sich als root an und führen Sie die geschützte
interaktive Einrichtung durch.

Die Bereitstellung erstellt einen eingeschränkten sudo-Benutzer, konfiguriert
UFW und Fail2ban, deaktiviert auf Wunsch den direkten root-SSH-Zugriff und
prüft das öffentliche Dashboard sowie die API-Authentifizierung. Die
Zugangshinweise befinden sich im Home-Verzeichnis des Administrators.

Erforderliche eingehende Ports sind TCP 22, 80 und 443 sowie UDP 3478. Bei
einer Hetzner Cloud Firewall muss das zustandslose UDP-Verhalten berücksichtigt
werden.

## Image-Inhalt

- Ubuntu 24.04 LTS
- NetBird Server 0.76.0 — AGPL-3.0
- NetBird Dashboard 2.90.8 — AGPL-3.0
- Traefik 3.7.10 — MIT
- Docker Engine und Compose — Apache-2.0

## Links

- [NetBird-Dokumentation](https://docs.netbird.io/)
- [NetBird-Support](https://docs.netbird.io/help/netbird-support)
- [Hetzner Cloud Dokumentation](https://docs.hetzner.com/de/cloud/)
