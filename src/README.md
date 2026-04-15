# AusbilderPro Suite – Quellcode

## Struktur

```
src/                    ← DU BIST HIER – Klartext-Quellcode
  AusbilderPro.html     
  AzubiPro.html         
  MitarbeiterPro.html   
  ArbeitgeberPro.html   
  HBZVerwaltung.html    
  README.md             ← Diese Datei

/*.html                 ← Obfuscated/Minified (deployed)
build.sh                ← src → obfuscate → root
```

## Wichtig

- **IMMER in `src/` bearbeiten** – die Dateien im Root sind verschleiert
- **`src/` nie löschen** – das ist dein einziger lesbarer Code
- Nach Änderungen: `bash build.sh` → dann git push

## Build ausführen

```bash
# Voraussetzung (einmalig):
npm install -g javascript-obfuscator

# Build:
cd /pfad/zum/repo
bash build.sh
git add -A
git commit -m "Update"
git push
```

## Falls Claude nicht verfügbar

1. Öffne die Datei in `src/` die du ändern willst
2. HTML + CSS ist im oberen Teil, JavaScript im `<script>` Block
3. Ändern, speichern, `bash build.sh`, git push
4. Oder: `src/` Datei direkt ins Root kopieren (dann ohne Obfuscation)

## Für neuen Claude-Chat

Claude greift immer auf `src/*.html` zu (Klartext). 
Der Workflow ist:
1. `src/` lesen und bearbeiten
2. `build.sh` ausführen  
3. Deployen

---
Stand: April 2026 | Stefan Mohr | IMMOJECK
