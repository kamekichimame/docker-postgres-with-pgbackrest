#!/bin/bash
set -euo pipefail

# 環境変数
CONFIG="${ENV_PGBACKREST_CONFIG_FILE_PATH:-/etc/pgbackrest/conf/pgbackrest.conf}"
STANZA="${ENV_PGBACKREST_STANZA:-postgres}"
FULL_BACKUP_INTERVAL_DAYS="${ENV_FULL_BACKUP_INTERVAL_DAYS:-7}"
LOCK_PATH="/var/lib/pgbackrest/lock"
SPOOL_PATH="/var/lib/pgbackrest/spool"

# ログプレフィックス
LOG_PREFIX="[pgbackrest-cronjob]"

# フルバックアップ日時記録ファイル
FULL_TIMESTAMP_FILE="$PGDATA/full_backup_timestamp.txt"

echo "${LOG_PREFIX} Backup started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "${LOG_PREFIX} Stanza: ${STANZA}"
echo "${LOG_PREFIX} Config file: ${CONFIG}"

# 前回のフルバックアップ日時をファイルから読み込む
if [ -f "$FULL_TIMESTAMP_FILE" ]; then
  LAST_FULL=$(cat "$FULL_TIMESTAMP_FILE" | tr -d '[:space:]')
  if [[ "$LAST_FULL" =~ ^[0-9]+$ ]]; then
    DAYS_SINCE_LAST_FULL=$(( ($(date +%s) - LAST_FULL) / 86400 ))
  else
    LAST_FULL=""
  fi
else
  LAST_FULL=""
fi

# 前回のフルバックアップ日時からの経過日数を基にバックアップタイプを決定
if [ -z "$LAST_FULL" ]; then
  echo "${LOG_PREFIX} No previous full backup. Executing full backup."
  BACKUP_TYPE="full"
else
  if [ "$DAYS_SINCE_LAST_FULL" -gt "$FULL_BACKUP_INTERVAL_DAYS" ]; then
    echo "${LOG_PREFIX} Last full backup was ${DAYS_SINCE_LAST_FULL} days ago. Executing full backup."
    BACKUP_TYPE="full"
  else
    echo "${LOG_PREFIX} Last full backup was ${DAYS_SINCE_LAST_FULL} days ago. Executing incremental backup."
    BACKUP_TYPE="incr"
  fi
fi

# バックアップ実行
pgbackrest --config="${CONFIG}" --stanza="${STANZA}" \
  --lock-path="${LOCK_PATH}" backup --type="${BACKUP_TYPE}" 2>&1 | sed 's/^/[pgBackRest] /'

# フルバックアップが成功したらタイムスタンプを更新
if [ "$BACKUP_TYPE" = "full" ]; then
  if [ $? -eq 0 ]; then
    date +%s > "$FULL_TIMESTAMP_FILE"
    echo "${LOG_PREFIX} Full backup completed. Timestamp updated to $(date +%s)."
  else
    echo "${LOG_PREFIX} Full backup failed. Timestamp not updated."
  fi
fi

echo "${LOG_PREFIX} Backup finished: $(date '+%Y-%m-%d %H:%M:%S')"