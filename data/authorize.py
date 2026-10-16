"""Trigger a one-time OAuth sign-in against the running bridge container.

Connecting with the bridge password makes the service start its --local-server-auth
flow: it logs a Microsoft sign-in URL and serves the redirect on port 8080.
Open that URL in your browser while an SSH tunnel forwards 8080 to the VPS.
When you finish signing in, this login completes and the token is saved.

Run via authorize.sh, not directly.
"""
import imaplib
import os
import ssl

HOST = os.environ.get('BRIDGE_CONTAINER', 'university-mail-bridge')  # the running service
USER = os.environ['BRIDGE_USER']
PASSWORD = os.environ['BRIDGE_PASSWORD']

# This hop is container-to-container on Docker's internal network, so the public
# certificate's hostname won't match; verification is not meaningful here.
ctx = ssl._create_unverified_context()

print('Connecting to the bridge to start sign-in (this blocks until you finish)...',
      flush=True)
imap = imaplib.IMAP4_SSL(HOST, 993, ssl_context=ctx)
imap.login(USER, PASSWORD)          # blocks here until the browser step is done
status, data = imap.select('INBOX', readonly=True)
count = data[0].decode() if status == 'OK' else '?'
imap.logout()
print('OK: signed in and INBOX reachable (%s messages).' % count, flush=True)
print('Use this same password in your mail client.', flush=True)
