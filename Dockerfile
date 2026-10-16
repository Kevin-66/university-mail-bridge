# University Mail Bridge — email-oauth2-proxy in a container for a VPS.
# Adds OAuth2 to plain IMAP/SMTP so a cloud mail client (e.g. Spark) can reach
# a Microsoft 365 mailbox whose tenant blocks the client's own app.
FROM python:3-slim

# Always install the latest releases at build time. cryptography ships
# manylinux wheels, so no compiler/GTK is needed. prompt_toolkit is only used
# for the interactive sign-in; harmless to include.
RUN pip install --no-cache-dir --upgrade \
        emailproxy \
        prompt_toolkit

# Run as a non-root user; /data (config + token cache) is a mounted volume.
RUN useradd --system --create-home --uid 10001 bridge
WORKDIR /data

USER bridge
ENTRYPOINT ["python", "-m", "emailproxy"]
# --local-server-auth lets the service (re)authorize headlessly: when there is
# no valid token it logs a sign-in URL and briefly serves the OAuth redirect on
# port 8080 (reach it via an SSH tunnel; see README). Normal token refresh is
# silent and needs none of this.
CMD ["--no-gui", "--local-server-auth", \
     "--config-file", "/data/emailproxy.config", \
     "--cache-store", "/data/tokens.cache", \
     "--log-file", "/dev/stdout"]
