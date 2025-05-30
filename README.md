# Log Rotation Manager

Script Bash pour automatiser la rotation des logs avec génération de rapports HTML et envoi par email.

## Fonctionnalités

- Rotation des logs selon la configuration `logrotate` ou méthode manuelle
- Nettoyage des anciens fichiers de log (> 30 jours par défaut)
- Surveillance de l'utilisation du disque avec seuil d'alerte configurable
- Génération d'un rapport HTML détaillé avec :
  - Statut d'utilisation des disques
  - Résumé des opérations
  - Détails des fichiers traités
  - Espace libéré
- Envoi du rapport par email via `msmtp`

## Prérequis

- Bash
- `logrotate` (installé par défaut sur la plupart des systèmes)
- `msmtp` pour l'envoi d'emails
- Outils standard : `du`, `find`, `date`, etc.

Installation des dépendances :
```bash
# Debian/Ubuntu
sudo apt-get install logrotate msmtp-mta
```
```bash
# RHEL/CentOS
sudo yum install logrotate msmtp
```
