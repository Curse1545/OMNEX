import importlib.util
import json
import pathlib
import threading
import unittest
import urllib.error
import urllib.request

path = pathlib.Path(__file__).parents[1] / 'distribution' / 'omnex_tools.py'
spec = importlib.util.spec_from_file_location('omnex_tools', path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ToolServerTests(unittest.TestCase):
    def setUp(self):
        helper.TOKEN = 'test-session-token-long-enough-for-local-testing'
        self.server = helper.ThreadingHTTPServer(('127.0.0.1', 0), helper.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path, token=None, origin=None, body=b'{}'):
        headers = {'Content-Type': 'application/json'}
        if token is not None:
            headers['X-OMNEX-Token'] = token
        if origin:
            headers['Origin'] = origin
        req = urllib.request.Request(f'http://127.0.0.1:{self.server.server_port}{path}', data=body, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=3) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def test_unauthorized_request_cannot_open_camera(self):
        self.assertEqual(self.request('/camera/start')[0], 403)
        self.assertIsNone(helper.CAMERA)

    def test_cross_origin_rejected_even_with_token(self):
        self.assertEqual(self.request('/camera/start', helper.TOKEN, 'https://example.com')[0], 403)
        self.assertIsNone(helper.CAMERA)

    def test_health_does_not_activate_devices(self):
        self.assertEqual(self.request('/health', helper.TOKEN), (200, {'ok': True}))
        self.assertIsNone(helper.CAMERA)
        self.assertIsNone(helper.VOICE_MODEL)

    def test_unknown_paths_and_large_payloads_fail(self):
        self.assertEqual(self.request('/shell', helper.TOKEN)[0], 404)
        self.assertEqual(self.request('/health', helper.TOKEN, body=b'x' * 20000)[0], 413)

    def test_invalid_camera_index_rejected_before_device_access(self):
        self.assertEqual(self.request('/camera/start', helper.TOKEN, body=b'{"index":99}')[0], 500)
        self.assertIsNone(helper.CAMERA)


if __name__ == '__main__':
    unittest.main()
