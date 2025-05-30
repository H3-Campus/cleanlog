#!/bin/bash

# Configuration
SERVER_NAME="$(hostname)"
EMAIL_DEST="admin@h3campus.fr"
LOG_DIR="/var/log"
RETENTION_DAYS=30
DATE=$(date +"%Y-%m-%d")
REPORT_FILE="/tmp/log_rotation_report_$DATE.html"
DISK_THRESHOLD=80 # Alerte si l'utilisation du disque dépasse ce pourcentage

# Couleurs pour le rapport HTML
COLOR_OK="#4CAF50"
COLOR_WARNING="#FFC107"
COLOR_ERROR="#F44336"
COLOR_HEADER="#2196F3"
COLOR_NORMAL="#000000"

# Fonction pour vérifier la présence des commandes nécessaires
check_dependencies() {
    local missing_deps=""
    
    # Vérifier logrotate
    if ! command -v logrotate >/dev/null 2>&1; then
        # Essayer les chemins standards
        if [ -x "/usr/sbin/logrotate" ]; then
            LOGROTATE_CMD="/usr/sbin/logrotate"
        elif [ -x "/sbin/logrotate" ]; then
            LOGROTATE_CMD="/sbin/logrotate"
        else
            missing_deps="$missing_deps logrotate"
        fi
    else
        LOGROTATE_CMD="logrotate"
    fi
    
    # Vérifier msmtp
    if ! command -v msmtp >/dev/null 2>&1; then
        missing_deps="$missing_deps msmtp"
    fi
    
    if [ -n "$missing_deps" ]; then
        echo "ERREUR: Commandes manquantes:$missing_deps"
        echo "Veuillez installer les paquets manquants:"
        echo "  sudo apt-get install logrotate msmtp-mta"
        echo "  ou"
        echo "  sudo yum install logrotate msmtp"
        return 1
    fi
    
    return 0
}

# Création du rapport HTML
create_html_report() {
    cat > $REPORT_FILE << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport de rotation des logs - $SERVER_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: ${COLOR_HEADER}; color: white; }
        .ok { color: ${COLOR_OK}; }
        .warning { color: ${COLOR_WARNING}; }
        .error { color: ${COLOR_ERROR}; }
        .section { margin-top: 25px; border-top: 1px solid #eee; padding-top: 10px; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>Rapport de rotation des logs - $SERVER_NAME</h1>
    <p>Date: $DATE</p>
    
    <div class="section">
        <h2>Utilisation du disque</h2>
        <table>
            <tr>
                <th>Système de fichiers</th>
                <th>Taille</th>
                <th>Utilisé</th>
                <th>Disponible</th>
                <th>Utilisation</th>
                <th>Monté sur</th>
                <th>Statut</th>
            </tr>
EOF

    # Ajouter les informations d'utilisation du disque au rapport
    df -h | grep -v "tmpfs\|udev" | tail -n +2 | while read fs size used avail use mounted; do
        usage_percent=$(echo $use | tr -d '%')
        if [ $usage_percent -ge $DISK_THRESHOLD ]; then
            status="<span class=\"error\">Critique ($use)</span>"
        elif [ $usage_percent -ge $(($DISK_THRESHOLD - 10)) ]; then
            status="<span class=\"warning\">Attention ($use)</span>"
        else
            status="<span class=\"ok\">Normal ($use)</span>"
        fi
        
        echo "<tr><td>$fs</td><td>$size</td><td>$used</td><td>$avail</td><td>$use</td><td>$mounted</td><td>$status</td></tr>" >> $REPORT_FILE
    done

    # Ajouter la section de rotation des logs
    cat >> $REPORT_FILE << EOF
        </table>
    </div>
    
    <div class="section">
        <h2>Résumé de la rotation des logs</h2>
        <table>
            <tr>
                <th>Action</th>
                <th>Résultat</th>
            </tr>
EOF
}

# Fonction pour ajouter une entrée au rapport
add_to_report() {
    local action=$1
    local result=$2
    local status=$3
    
    case $status in
        "ok") style="class=\"ok\"" ;;
        "warning") style="class=\"warning\"" ;;
        "error") style="class=\"error\"" ;;
        *) style="" ;;
    esac
    
    echo "<tr><td>$action</td><td $style>$result</td></tr>" >> $REPORT_FILE
}

# Fonction pour finaliser le rapport HTML
finalize_report() {
    # Ajouter l'espace utilisé par les logs avant et après la rotation
    local before_size=$1
    local after_size=$2
    local space_saved=$(($before_size - $after_size))
    local cleaned_files_info="$3"
    
    cat >> $REPORT_FILE << EOF
            <tr>
                <td>Espace utilisé avant rotation</td>
                <td>$(echo $before_size | awk '{printf "%.2f MB", $1/1024}')</td>
            </tr>
            <tr>
                <td>Espace utilisé après rotation</td>
                <td>$(echo $after_size | awk '{printf "%.2f MB", $1/1024}')</td>
            </tr>
            <tr>
                <td>Espace libéré</td>
                <td class="ok">$(echo $space_saved | awk '{printf "%.2f MB", $1/1024}')</td>
            </tr>
        </table>
    </div>
    
    <div class="section">
        <h2>Détails des fichiers traités</h2>
        <pre>$cleaned_files_info</pre>
    </div>
</body>
</html>
EOF
}

# Fonction pour envoyer le rapport par email
send_email_report() {
    # Vérifier si msmtp est disponible
    if ! command -v msmtp >/dev/null 2>&1; then
        echo "ATTENTION: msmtp non disponible, rapport sauvegardé dans $REPORT_FILE"
        add_to_report "Envoi du rapport par email" "Échec: msmtp non disponible" "error"
        return 1
    fi
    
    # Configuration du sujet et des destinataires
    SUBJECT="[RAPPORT] - Rotation des logs : $SERVER_NAME"
    
    # Envoi de l'email avec msmtp
    (
        echo "To: $EMAIL_DEST"
        echo "From: notifs@h3campus.fr"
        echo "Subject: $SUBJECT"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        cat $REPORT_FILE
    ) | msmtp --from=noreply@$SERVER_NAME -t $EMAIL_DEST 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Rapport envoyé avec succès à $EMAIL_DEST"
        add_to_report "Envoi du rapport par email" "Succès vers $EMAIL_DEST" "ok"
    else
        echo "Erreur lors de l'envoi du rapport à $EMAIL_DEST"
        echo "Rapport sauvegardé dans $REPORT_FILE"
        add_to_report "Envoi du rapport par email" "Échec vers $EMAIL_DEST (rapport sauvegardé localement)" "warning"
    fi
}

# Fonction pour effectuer la rotation manuelle des logs
manual_log_rotation() {
    local rotation_output=""
    local files_rotated=0
    
    # Vérifier la configuration de logrotate
    if [ ! -f "/etc/logrotate.conf" ]; then
        echo "ATTENTION: /etc/logrotate.conf introuvable, rotation manuelle"
        add_to_report "Configuration logrotate" "Fichier /etc/logrotate.conf introuvable" "warning"
        
        # Rotation manuelle des fichiers de log courants
        for logfile in "$LOG_DIR"/*.log; do
            if [ -f "$logfile" ] && [ -s "$logfile" ]; then
                # Créer une sauvegarde avec timestamp
                backup_file="${logfile}.$(date +%Y%m%d-%H%M%S)"
                if cp "$logfile" "$backup_file" && > "$logfile"; then
                    rotation_output="$rotation_output\nRotation manuelle: $logfile -> $backup_file"
                    files_rotated=$((files_rotated + 1))
                fi
            fi
        done
        
        if [ $files_rotated -gt 0 ]; then
            add_to_report "Rotation manuelle des logs" "Succès: $files_rotated fichiers traités" "ok"
        else
            add_to_report "Rotation manuelle des logs" "Aucun fichier à traiter" "warning"
        fi
    else
        # Utiliser logrotate standard
        rotation_output=$($LOGROTATE_CMD -f /etc/logrotate.conf 2>&1)
        logrotate_status=$?
        
        if [ $logrotate_status -eq 0 ]; then
            add_to_report "Rotation des logs (logrotate)" "Succès" "ok"
        else
            add_to_report "Rotation des logs (logrotate)" "Échec: $rotation_output" "error"
        fi
    fi
    
    echo "$rotation_output"
}

# Programme principal
main() {
    echo "=== Début du nettoyage des logs - $(date) ==="
    
    # Vérifier les dépendances
    if ! check_dependencies; then
        exit 1
    fi
    
    # Calculer l'espace utilisé par les logs avant la rotation
    BEFORE_SIZE=$(du -sm $LOG_DIR 2>/dev/null | cut -f1)
    if [ -z "$BEFORE_SIZE" ]; then
        BEFORE_SIZE=0
    fi
    
    echo "Espace utilisé avant rotation: $(echo $BEFORE_SIZE | awk '{printf "%.2f MB", $1/1024}')"
    
    # Créer le rapport HTML
    create_html_report
    
    # Effectuer la rotation des logs
    echo "Rotation des logs en cours..."
    rotation_details=$(manual_log_rotation)
    
    # Rechercher et supprimer les anciens fichiers de log (plus anciens que RETENTION_DAYS)
    echo "Nettoyage des anciens logs (> $RETENTION_DAYS jours)..."
    
    # Lister les fichiers qui vont être supprimés
    old_files_list=$(find $LOG_DIR -type f \( -name "*.gz" -o -name "*.log.*" \) -mtime +$RETENTION_DAYS 2>/dev/null)
    
    if [ -n "$old_files_list" ]; then
        # Afficher les détails des fichiers avant suppression
        cleaned_files=$(echo "$old_files_list" | xargs ls -lh 2>/dev/null)
        
        # Supprimer les anciens fichiers
        old_files_result=$(echo "$old_files_list" | xargs rm -f 2>&1)
        old_files_status=$?
        
        if [ $old_files_status -eq 0 ]; then
            files_count=$(echo "$old_files_list" | wc -l)
            add_to_report "Suppression des anciens logs" "Succès: $files_count fichiers supprimés" "ok"
        else
            add_to_report "Suppression des anciens logs" "Échec: $old_files_result" "error"
            cleaned_files="Erreur lors de la suppression: $old_files_result"
        fi
    else
        add_to_report "Suppression des anciens logs" "Aucun fichier ancien à supprimer" "ok"
        cleaned_files="Aucun fichier de plus de $RETENTION_DAYS jours trouvé"
    fi
    
    # Calculer l'espace utilisé par les logs après la rotation
    AFTER_SIZE=$(du -sm $LOG_DIR 2>/dev/null | cut -f1)
    if [ -z "$AFTER_SIZE" ]; then
        AFTER_SIZE=0
    fi
    
    echo "Espace utilisé après rotation: $(echo $AFTER_SIZE | awk '{printf "%.2f MB", $1/1024}')"
    
    # Finaliser le rapport
    all_details="=== Rotation des logs ===<br>$rotation_details<br><br>=== Fichiers nettoyés ===<br>$cleaned_files"
    finalize_report $BEFORE_SIZE $AFTER_SIZE "$all_details"
    
    # Envoyer le rapport par email
    echo "Envoi du rapport..."
    send_email_report
    
    # Afficher un résumé
    space_saved=$(($BEFORE_SIZE - $AFTER_SIZE))
    echo "=== Résumé ==="
    echo "Espace libéré: $(echo $space_saved | awk '{printf "%.2f MB", $1/1024}')"
    echo "Rapport HTML: $REPORT_FILE"
    
    echo "=== Fin du nettoyage des logs - $(date) ==="
}

# Exécuter le programme principal
main

exit 0
