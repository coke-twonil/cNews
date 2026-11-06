import sys
import unittest
from unittest.mock import patch,MagicMock
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import nntp_connection as connection
from nntp_ranges import article_numbers,number_ranges,selected_headers

class ConnectionTests(unittest.TestCase):
    def test_endpoint_and_tls(self):
        self.assertEqual(connection.endpoint({'host':'NEWS.TWONIL.HK','port':119}),('news.twonil.hk',119,False))
        self.assertTrue(connection.endpoint({'host':'news.example.com','port':563})[2])
        for host in ['https://news.example.com','user@news.example.com','host\r\nQUIT','bad..name']:
            with self.assertRaises(ValueError):connection.endpoint({'host':host})
    def test_private_and_mixed_dns_addresses_never_connect(self):
        for ip in ['127.0.0.1','192.168.1.1','169.254.169.254','::1','::ffff:127.0.0.1']:
            addresses=[(2,1,6,'',(ip,119))]
            with patch.object(connection.socket,'getaddrinfo',return_value=addresses),patch.object(connection.socket,'socket') as sock:
                with self.assertRaises(ValueError):connection.public_socket('news.example.com',119,5)
                sock.assert_not_called()
    def test_validated_public_ip_is_pinned(self):
        addresses=[(2,1,6,'',('8.8.8.8',119))]
        with patch.object(connection.socket,'getaddrinfo',return_value=addresses) as dns,patch.object(connection.socket,'socket') as sock:
            self.assertIs(connection.public_socket('news.example.com',119,5),sock.return_value)
            sock.return_value.connect.assert_called_once_with(('8.8.8.8',119));self.assertEqual(dns.call_count,1)
    def test_no_implicit_local_credentials(self):
        with patch.object(connection,'PublicNNTP') as client:
            connection.open_client({'host':'news.example.com','port':119})
            self.assertFalse(client.call_args.kwargs['usenetrc'])

class HeaderTests(unittest.TestCase):
    def test_exact_inventory_and_no_unselected_header_download(self):
        client=MagicMock();client._longcmdstring.return_value=('211 group',['10','12','12','15'])
        self.assertEqual(article_numbers(client,'test.test'),[10,12,15])
        client.over.side_effect=lambda span:('224',[(n,{}) for n in range(span[0],span[1]+1)])
        self.assertEqual(number_ranges([1,2,3,8,10,11]),[[1,3],[8,8],[10,11]])
        self.assertEqual([n for n,_ in selected_headers(client,[10,12,15])],[10,12,15])
        self.assertEqual([call.args[0] for call in client.over.call_args_list],[(10,10),(12,12),(15,15)])
    def test_batch_limit_and_expired_range(self):
        client=MagicMock()
        for numbers in [list(range(1,502)),[True],[-1],'1,2']:
            with self.assertRaises(ValueError):selected_headers(client,numbers)
        import nntplib
        client.over.side_effect=nntplib.NNTPTemporaryError('423 No articles')
        self.assertEqual(selected_headers(client,[123]),[])
