# University Mail Bridge — email-oauth2-proxy in a container for a VPS.
# Adds OAuth2 to plain IMAP/SMTP so a cloud mail client (e.g. Spark) can reach
# a Microsoft 365 mailbox whose tenant blocks the client's own app.
FROM python:3-slim

# Always the latest release at build time. The published image is rebuilt
# weekly without layer caching, so this really is current. cryptography ships
# manylinux wheels, so no compiler is needed; prompt_toolkit comes along as a
# dependency of emailproxy itself.
RUN pip install --no-cache-dir --upgrade emailproxy

# /data (config, certs, token cache) is a bind mount from the host. The
# container starts as root only so the entrypoint can switch to the owner of
# that folder; the proxy itself never runs as root unless /data is root-owned.
COPY entrypoint.py /entrypoint.py
WORKDIR /data

ENTRYPOINT ["python", "/entrypoint.py"]
# --local-server-auth lets the service (re)authorize headlessly: when there is
# no valid token it logs a sign-in URL and briefly serves the OAuth redirect on
# port 8080 (reach it via an SSH tunnel; see README). Normal token refresh is
# silent and needs none of this.
CMD ["--no-gui", "--local-server-auth", \
     "--config-file", "/data/emailproxy.config", \
     "--cache-store", "/data/tokens.cache", \
     "--log-file", "/dev/stdout"]
