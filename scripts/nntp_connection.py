"""NNTP destinations selected in the local reader; no implicit credentials."""
import ipaddress
import nntplib
import re
import socket
import ssl

DEFAULT_HOST = 'news.twonil.hk'


def endpoint(values):
    host = values.get('host', DEFAULT_HOST)
    if not isinstance(host,str):
        raise ValueError('Invalid server')
    host = host.strip().rstrip('.').lower()
    try:
        ipaddress.ip_address(host)
    except ValueError:
        host = host.encode('idna').decode('ascii')
        if len(host)>253 or not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?',host) or '..' in host or any(len(label)>63 for label in host.split('.')):
            raise ValueError('Invalid server')
    port = int(values.get('port') or 119)
    if not 1 <= port <= 65535:
        raise ValueError('Invalid port')
    tls = port == 563 or values.get('tls') in (True,1,'1','true')
    return host,port,tls


def public_socket(host,port,timeout):
    addresses = socket.getaddrinfo(host,port,type=socket.SOCK_STREAM)
    if not addresses:
        raise OSError('Server address not found')
    # Pin the validated IP. Never re-resolve after validating (DNS rebinding).
    for _,_,_,_,address in addresses:
        ip = ipaddress.ip_address(address[0])
        ip = getattr(ip,'ipv4_mapped',None) or ip
        if not ip.is_global:
            raise ValueError('此原型只連接公開 NNTP server，唔接受本機／私人網絡地址。')
    failure = None
    for family,kind,protocol,_,address in addresses:
        sock=socket.socket(family,kind,protocol)
        try:
            sock.settimeout(timeout);sock.connect(address);return sock
        except OSError as error:
            failure=error;sock.close()
    raise failure or OSError('Unable to connect')


class PublicNNTP(nntplib.NNTP):
    def _create_socket(self,timeout):
        return public_socket(self.host,self.port,timeout)


class PublicNNTPSsl(nntplib.NNTP_SSL):
    def _create_socket(self,timeout):
        sock=public_socket(self.host,self.port,timeout)
        try:
            return (self.ssl_context or ssl.create_default_context()).wrap_socket(sock,server_hostname=self.host)
        except Exception:
            sock.close();raise


def open_client(values,timeout=12):
    host,port,tls=endpoint(values)
    cls=PublicNNTPSsl if tls else PublicNNTP
    return cls(host,port,readermode=True,usenetrc=False,timeout=timeout)
