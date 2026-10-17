"""Start emailproxy as the owner of /data.

/data is a bind mount from the host, so everything in it (config, TLS key,
token cache) belongs to whichever host user cloned the repo. Running the proxy
as that same uid/gid lets it read the private key and write the token cache
with no chown step on the host. The container therefore starts as root and
drops to that user here, before anything else runs. If /data is owned by root
(you cloned and run as root on the VPS), the proxy simply stays root.
"""
import os
import sys

DATA = '/data'

owner = os.stat(DATA)
if os.getuid() == 0 and owner.st_uid != 0:
    os.setgroups([])
    os.setgid(owner.st_gid)
    os.setuid(owner.st_uid)
print('Running as uid %d / gid %d (the owner of %s)' % (os.getuid(), os.getgid(), DATA), flush=True)

os.execv(sys.executable, [sys.executable, '-m', 'emailproxy', *sys.argv[1:]])
