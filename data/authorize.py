"""Trigger a one-time OAuth sign-in on the running bridge.

Reads the address and the bridge password as two lines on stdin, then logs in
to the proxy on this container's own port 993. A login for an account with no
saved token makes the proxy start its --local-server-auth flow: it logs a
Microsoft sign-in URL and serves the redirect on port 8080. Open that URL in
your browser while an SSH tunnel forwards 8080 to the VPS. When you finish
signing in, this login completes and the token is saved.

Run via authorize.sh, not directly.
"""
import imaplib
import ssl
import sys

user = sys.stdin.readline().strip()
password = sys.stdin.readline().rstrip('\n')
if not user or not password:
    sys.exit('Expected the address and the password as two lines on stdin.')

# Same container, so the public certificate's hostname can't match 127.0.0.1;
# verification is not meaningful on this hop.
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

print('Connecting to the bridge to start sign-in (this blocks until you finish)...',
      flush=True)
imap = imaplib.IMAP4_SSL('127.0.0.1', 993, ssl_context=ctx)
imap.login(user, password)          # blocks here until the browser step is done
status, data = imap.select('INBOX', readonly=True)
count = data[0].decode() if status == 'OK' else '?'
imap.logout()
print('OK: signed in and INBOX reachable (%s messages).' % count, flush=True)
print('Use this same password in your mail client.', flush=True)
