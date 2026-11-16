# Kanidm identity server for Railway.
# The official image is FROM scratch (no shell) and Kanidm only serves HTTPS.
# This wrapper adds a static busybox (for the start script) and Caddy, which
# serves plain HTTP on $PORT for Railway's edge and proxies to Kanidm's
# loopback TLS listener.
FROM busybox:1.37.0-musl@sha256:f6a95d611e0a8780fabdb2aec43e31275b2720dfefa3e41b16835bfc42454478 AS busybox
FROM caddy:2.11.9@sha256:4e2425f6009577e7c651010f16679c28f7d12df3e7b1914f941a7a3370746b3c AS caddy

FROM kanidm/server:1.12.1@sha256:77198131f28116203e105d2e42214203757d113a694f35de545669e75db5c96f

COPY --from=busybox /bin/busybox /bin/busybox
RUN ["/bin/busybox", "mkdir", "-p", "/usr/bin", "/tmp", "/etc/caddy"]
RUN ["/bin/busybox", "--install", "-s", "/bin"]
RUN chmod 1777 /tmp
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /start.sh

ENV PORT=8080 \
    XDG_DATA_HOME=/tmp/caddy-data \
    XDG_CONFIG_HOME=/tmp/caddy-config

WORKDIR /data
EXPOSE 8080

# Replace the image's Docker HEALTHCHECK (it targets the TLS listener on
# 0.0.0.0:8443, which this wrapper keeps on loopback). Railway uses /status.
HEALTHCHECK NONE

ENTRYPOINT ["/bin/sh", "/start.sh"]
