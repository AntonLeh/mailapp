# Mail (Freenet / IONOS)

Mail-Client für Windows und Android mit integriertem PDF-Reader. Verbindet sich per IMAP (Empfang) und SMTP (Versand) mit deinem Postfach.

## Installieren

1. Im Tab **Actions** dieses Repositorys den letzten erfolgreichen Lauf „Build“ öffnen.
2. Unter **Artifacts** herunterladen:
   - `mailapp-android-apk` → `app-release.apk` auf das Handy kopieren und installieren (Installation aus unbekannten Quellen erlauben).
   - `mailapp-windows` → ZIP entpacken und `mailapp.exe` starten. Windows warnt bei nicht signierten Apps (SmartScreen). Dann „Trotzdem ausführen“.

## Einrichten

Provider wählen (Freenet oder IONOS), E-Mail-Adresse und Passwort eingeben. Server und Ports sind voreingestellt und können geändert werden. Das Passwort wird im Systemschlüsselbund gespeichert, nicht in einer Datei.

Port 465 = verschlüsselt ab Verbindungsstart, Port 587 = STARTTLS.

## Funktionen (Version 0.1)

- Posteingang: die letzten 30 Nachrichten, aktualisieren per Button
- Nachricht lesen, Anhänge auflisten
- PDF-Anhänge direkt im integrierten Reader öffnen
- Neue Nachricht als Text senden

Noch nicht enthalten: Anhänge versenden, Ordner außer Posteingang, lokaler Offline-Cache, Antworten/Weiterleiten.

## Entwicklung

Flutter-Projekt. Der Workflow erzeugt die Plattform-Dateien (`flutter create`) bei jedem Build neu, daher liegt im Repository nur der Code in `lib/`.
