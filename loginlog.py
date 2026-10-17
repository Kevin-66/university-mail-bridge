"""Start emailproxy, and also log the client's IP address with every failed login.

emailproxy logs a client's address only when it connects, and a failed login only with the
account name, so a log watcher such as fail2ban can't tell whom to block. This notes which
client emailproxy is serving while it checks a login, and adds one line when the login fails:

    Failed login from 203.0.113.5 (IMAP) for account someone@example.com

Nothing else changes; the command-line arguments go to emailproxy as they are.
"""
import emailproxy

_client = None  # (connection, proxy type) being served; emailproxy runs every connection on one thread
_depth = 0  # get_oauth2_credentials retries by calling itself; only the outermost answer counts


def _client_host(connection):
    # "<client host:port>-{<local host:port>}-<server host:port>", set when the client connects
    address = getattr(connection, 'debug_address_string', '') or ''
    return address.split('-{', 1)[0].rsplit(':', 1)[0].strip('[]')


def _serving(client_of, handle_read):
    def wrapped(self):
        global _client
        previous, _client = _client, (client_of(self), self.proxy_type)
        try:
            return handle_read(self)
        finally:
            _client = previous
    return wrapped


# IMAP checks the login while reading from the client; SMTP while reading the server's reply.
emailproxy.OAuth2ClientConnection.handle_read = _serving(
    lambda client: client, emailproxy.OAuth2ClientConnection.handle_read)
emailproxy.OAuth2ServerConnection.handle_read = _serving(
    lambda server: server.client_connection, emailproxy.OAuth2ServerConnection.handle_read)

_get_oauth2_credentials = emailproxy.OAuth2Helper.get_oauth2_credentials


def get_oauth2_credentials(username, password, *args, **kwargs):
    global _depth
    _depth += 1
    try:
        success, result = _get_oauth2_credentials(username, password, *args, **kwargs)
    finally:
        _depth -= 1
    if not success and _depth == 0 and _client:
        connection, proxy_type = _client
        host = _client_host(connection)
        if host:
            emailproxy.Log.info('Failed login from %s (%s) for account %s' % (host, proxy_type, username))
    return success, result


emailproxy.OAuth2Helper.get_oauth2_credentials = staticmethod(get_oauth2_credentials)

if __name__ == '__main__':
    emailproxy.App()
