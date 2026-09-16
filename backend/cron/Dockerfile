FROM alpine:3.20

RUN apk add --no-cache curl

COPY purge_deleted_sessions.sh /usr/local/bin/purge_deleted_sessions.sh
RUN chmod +x /usr/local/bin/purge_deleted_sessions.sh

COPY crontab /etc/crontabs/root

CMD ["crond", "-f", "-l", "2"]
