ConEmu Settings
===============

Contains ConEmu.xml exported from a working machine
(07. Alim Desktop workstation 11 - 10 dec 2024).

Script 48 (install-conemu) handles sync automatically:
1. Installs ConEmu via `choco install conemu -y`
2. Copies ConEmu.xml to %APPDATA%\ConEmu\ConEmu.xml
   (creating the folder if missing)
3. If an existing ConEmu.xml is present, it is backed up to
   ConEmu.xml.bak.<timestamp> before being overwritten.

ConEmu reads ConEmu.xml from %APPDATA%\ConEmu on startup.

To export your current ConEmu settings to this folder:
  .\run.ps1 -I 48 -- export

This copies %APPDATA%\ConEmu\ConEmu.xml into this folder.
Files larger than 2 MB are skipped (ConEmu.xml is normally <500 KB).

Usage:
  .\run.ps1 install conemu            # Install ConEmu + sync settings
  .\run.ps1 install conemu-settings   # Sync settings only
  .\run.ps1 -I 48 -- export          # Export settings from machine to repo
