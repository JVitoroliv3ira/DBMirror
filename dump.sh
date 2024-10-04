#!/bin/bash

set -e

if ! command -v sqlcmd &> /dev/null; then
    echo "❌ sqlcmd não encontrado. Certifique-se de que o mssql-tools está instalado e no PATH."
    exit 1
fi

CONFIG_FILE="config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Arquivo $CONFIG_FILE não encontrado! Certifique-se de que ele está no diretório correto."
    exit 1
fi

draw_progress_bar() {
    local progress=$1
    local bar_width=30

    local completed=$((progress * bar_width / 100))
    local remaining=$((bar_width - completed))

    local progress_bar=$(printf "%0.s#" $(seq 1 "$completed"))
    local empty_bar=$(printf "%0.s-" $(seq 1 "$remaining"))

    printf "\r[%s%s] %d%%" "$progress_bar" "$empty_bar" "$progress"
}

restore_database() {
    local origin_host="$1"
    local origin_user="$2"
    local origin_password="$3"
    local origin_database="$4"
    local destination_host="$5"
    local destination_user="$6"
    local destination_password="$7"
    local destination_database="$8"

    local backup_file="/tmp/${origin_database}.bak"

    echo -e "\n============================="
    echo "🔄  Iniciando processamento do banco: $origin_database (origem: $origin_host, destino: $destination_database)"
    draw_progress_bar 5

    echo -e "\n📦 Criando backup do banco de dados '$origin_database' em '$origin_host'..."
    draw_progress_bar 20
    sqlcmd -b -S "$origin_host" -U "$origin_user" -P "$origin_password" \
        -Q "SET NOCOUNT ON; BACKUP DATABASE [$origin_database] TO DISK = N'$backup_file' WITH INIT, SKIP, NOFORMAT, STATS = 10;"

    draw_progress_bar 40
    echo -e "\n✅ Backup criado com sucesso para o banco '$origin_database'!"

    echo "🔍 Obtendo nomes lógicos dos arquivos do backup..."
    draw_progress_bar 50
    logical_names=$(sqlcmd -b -S "$origin_host" -U "$origin_user" -P "$origin_password" \
        -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$backup_file'" \
        -h -1 -s"," | tr -d '\r')

    if [[ -z "$logical_names" ]]; then
        echo "❌ Não foi possível obter os nomes lógicos dos arquivos do backup."
        exit 1
    fi

    logical_data=$(echo "$logical_names" | head -n1 | cut -d',' -f1 | xargs)
    logical_log=$(echo "$logical_names" | tail -n1 | cut -d',' -f1 | xargs)

    echo "📝 Nomes lógicos: Data='$logical_data', Log='$logical_log'"

    echo "🔄 Restaurando o banco '$destination_database' no destino..."
    draw_progress_bar 60
    sqlcmd -b -S "$destination_host" -U "$destination_user" -P "$destination_password" -Q "
    RESTORE DATABASE [$destination_database]
    FROM DISK = N'$backup_file'
    WITH MOVE '$logical_data' TO '/var/opt/mssql/data/${destination_database}.mdf',
         MOVE '$logical_log' TO '/var/opt/mssql/data/${destination_database}.ldf',
         REPLACE;"

    draw_progress_bar 100
    echo -e "\n✅ Banco '$destination_database' restaurado com sucesso no destino!"
    echo "============================="
}

echo "📜 Lendo credenciais de banco do arquivo $CONFIG_FILE..."
db_count=$(jq '.databases | length' "$CONFIG_FILE")

for (( i=0; i<db_count; i++ )); do
    origin_host=$(jq -r ".databases[$i].origin_host" "$CONFIG_FILE")
    origin_user=$(jq -r ".databases[$i].origin_user" "$CONFIG_FILE")
    origin_password=$(jq -r ".databases[$i].origin_password" "$CONFIG_FILE")
    origin_database=$(jq -r ".databases[$i].origin_database" "$CONFIG_FILE")
    destination_host=$(jq -r ".databases[$i].destination_host" "$CONFIG_FILE")
    destination_user=$(jq -r ".databases[$i].destination_user" "$CONFIG_FILE")
    destination_password=$(jq -r ".databases[$i].destination_password" "$CONFIG_FILE")
    destination_database=$(jq -r ".databases[$i].destination_database" "$CONFIG_FILE")

    restore_database "$origin_host" "$origin_user" "$origin_password" "$origin_database" "$destination_host" "$destination_user" "$destination_password" "$destination_database"
done

echo "🚀 Processamento de todos os bancos concluído!"
