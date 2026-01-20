# PostgreSQL with pgBackRest Docker Image
Dockerイメージ: `yourusername/postgres-pgbackrest`
PostgreSQL公式イメージにpgBackRestバックアップ機能を統合したDockerイメージです。自動バックアップとWALアーカイブをサポートします。
<br><br>
## クイックスタート
### 基本使用

```bash
docker run -d \
  --name postgres-pgbackrest \
  -e POSTGRES_PASSWORD=yourpassword \
  -e ENV_PGBACKREST_STANZA=mydb \
  yourusername/postgres-pgbackrest:latest
```

&nbsp;
### docker-compose.yml 例

```yaml
services:
  postgres:
    image: yourusername/postgres-pgbackrest:latest
    environment:
      POSTGRES_PASSWORD: securepassword123
      POSTGRES_DB: myappdb
      ENV_PGBACKREST_STANZA: production
      ENV_PGBACKREST_CRON_SCHEDULE: "0 2 * * *"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - pgbackrest_repo:/var/lib/pgbackrest
    ports:
      - "5432:5432"

volumes:
  postgres_data:
  pgbackrest_repo:
```

&nbsp;
## 環境変数
### PostgreSQL環境変数
- `POSTGRES_PASSWORD` - **必須** - PostgreSQLスーパーユーザーパスワード
- `POSTGRES_USER` - (デフォルト: `postgres`) - PostgreSQLユーザー名
- `POSTGRES_DB` - (デフォルト: `POSTGRES_USER`と同じ) - 作成するデータベース名
- `PGDATA` - (デフォルト: `/var/lib/postgresql/data`) - データディレクトリ
### pgBackRest環境変数
- `ENV_PGBACKREST_STANZA` - (デフォルト: `${POSTGRES_DB:-postgres}`) - pgBackRestスタンザ名。バックアップの論理グループ。
- `ENV_PGBACKREST_CRON_SCHEDULE` - (デフォルト: `"0 0 * * *"`) - バックアップスケジュール（cron形式）。
    - `"0 2 * * *"` = 毎日2:00
    - `"*/30 * * * *"` = 30分ごと
    - `"0 */6 * * *"` = 6時間ごと
- `ENV_PGBACKREST_CONFIG_FILE_PATH` - (デフォルト: `/etc/pgbackrest/conf/pgbackrest.conf`) - 設定ファイルパス

&nbsp;
## バックアップスケジュール例
```bash
# 毎日午前2時
ENV_PGBACKREST_CRON_SCHEDULE="0 2 * * *"

# 6時間ごと
ENV_PGBACKREST_CRON_SCHEDULE="0 */6 * * *"

# 30分ごと（開発用）
ENV_PGBACKREST_CRON_SCHEDULE="*/30 * * * *"

# 毎週日曜日午前3時
ENV_PGBACKREST_CRON_SCHEDULE="0 3 * * 0"
```

&nbsp;
## ボリューム設定
### 必須ボリューム

```yaml
volumes:
  - postgres_data:/var/lib/postgresql/data    # PostgreSQLデータ
  - pgbackrest_repo:/var/lib/pgbackrest       # pgBackRestリポジトリ
```
### オプションボリューム
```yaml
# カスタムconfigファイル
volumes:
  - ./custom.conf:/etc/postgresql/postgresql.conf:ro
  - ./pgbackrest.conf:/etc/pgbackrest/conf/pgbackrest.conf:ro
```

&nbsp;
## バックアップ管理
### 手動バックアップ
```bash
docker exec <container> pgbackrest --stanza=<stanza-name> backup
```
### バックアップ情報確認
```bash
docker exec <container> pgbackrest info
```
### リストア
```bash
# 最新バックアップから
docker exec <container> pgbackrest --stanza=<stanza> restore
  
# 特定の時点にリストア
docker exec <container> pgbackrest --stanza=<stanza> \
  --type=time --target="2024-01-19 12:00:00" restore
```

&nbsp;
## ログ確認
```bash
# すべてのログ
docker logs <container>

# バックアップ関連ログのみ
docker logs <container> | grep -E "(backup|archive)"

# PostgreSQLログのみ
docker logs <container> | grep "\[postgres\]"

# バックアップジョブログのみ
docker logs <container> | grep "\[pgbackrest-cron\]"
```