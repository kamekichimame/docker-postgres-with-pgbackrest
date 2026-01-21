FROM postgres:18-alpine

LABEL version="1.0"
LABEL description="PostgreSQL with pgBackRest and automated backups"

RUN apk add --no-cache \
    pgbackrest \
    bash \
    tzdata \
    jq \
    gettext \
    && rm -rf /var/cache/apk/*

# supercronicをダウンロード
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.26/supercronic-linux-amd64
ENV SUPERCRONIC=supercronic

# supercronicをインストール, cronjobファイル用のディレクトリ作成
RUN wget "$SUPERCRONIC_URL" -O "/usr/local/bin/$SUPERCRONIC" \
    && chmod +x "/usr/local/bin/$SUPERCRONIC" \
    && mkdir -p /etc/cronjobs \
    && chown -R postgres:postgres /etc/cronjobs \
    && chmod 700 /etc/cronjobs

# pgBackRest 設定
RUN mkdir -p /etc/pgbackrest/conf /var/log/pgbackrest /var/lib/pgbackrest/{lock,spool} /etc/postgresql \
    && chown -R postgres:postgres /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest /etc/postgresql \
    && chmod -R 750 /etc/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest

# pgbackrest設定ファイルのテンプレートをCOPY
COPY --chown=postgres:postgres --chmod=440 pgbackrest.conf.template /etc/pgbackrest/conf/pgbackrest.conf.template

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

COPY --chown=postgres:postgres setup.sh /
RUN chmod +x /setup.sh

COPY --chown=postgres:postgres pgbackrest-cronjob.sh /etc/cronjobs/pgbackrest-cronjob.sh
RUN chmod +x /etc/cronjobs/pgbackrest-cronjob.sh

RUN mkdir -p /etc/cronjobs \
    && chown -R postgres:postgres /etc/cronjobs \
    && chmod 700 /etc/cronjobs

ENTRYPOINT ["/entrypoint.sh"]
CMD ["postgres"]