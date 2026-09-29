"""OMNEX desktop tools. Loopback only; camera/mic are explicit user actions."""
import base64
import hmac
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.environ.get('OMNEX_TOOLS_TOKEN', '')
CAMERA = None
CAMERA_LOCK = threading.Lock()
VOICE_LOCK = threading.Lock()
MIC_STOP = threading.Event()
VOICE_MODEL = None
CASCADE = None
LAST_FRAME = 0.0


def camera_stop():
    global CAMERA
    with CAMERA_LOCK:
        if CAMERA is not None:
            CAMERA.release()
            CAMERA = None


def camera_start(index=0):
    global CAMERA, CASCADE, LAST_FRAME
    import cv2
    camera_stop()
    with CAMERA_LOCK:
        candidate = cv2.VideoCapture(index, cv2.CAP_DSHOW if sys.platform == 'win32' else cv2.CAP_ANY)
        if not candidate.isOpened():
            candidate.release()
            raise RuntimeError('Kamera acilamadi. Windows kamera iznini ve diger uygulamalari kontrol et.')
        candidate.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        candidate.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        CAMERA = candidate
        CASCADE = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        LAST_FRAME = time.monotonic()
    return {'ok': True}


def frame():
    global LAST_FRAME
    import cv2
    with CAMERA_LOCK:
        if CAMERA is None:
            raise RuntimeError('Kamera kapali.')
        ok, image = CAMERA.read()
        if not ok:
            raise RuntimeError('Kameradan goruntu alinamadi.')
        LAST_FRAME = time.monotonic()
        image = cv2.resize(image, (640, 480))
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        faces = CASCADE.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=5, minSize=(50, 50))
        ok, jpeg = cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 70])
        if not ok:
            raise RuntimeError('Goruntu kodlanamadi.')
        return {'jpeg': base64.b64encode(jpeg).decode('ascii'), 'faces': [[int(n) for n in face] for face in faces], 'width': 640, 'height': 480}


def prepare_voice():
    global VOICE_MODEL
    with VOICE_LOCK:
        if VOICE_MODEL is None:
            from faster_whisper import WhisperModel
            root = os.environ.get('OMNEX_VOICE_CACHE', os.path.join(os.path.dirname(__file__), 'voice-model'))
            os.makedirs(root, exist_ok=True)
            VOICE_MODEL = WhisperModel('base', device='cpu', compute_type='int8', cpu_threads=2, num_workers=1, download_root=root)
    return {'ok': True}


def listen():
    import numpy as np
    import sounddevice as sd
    if not VOICE_LOCK.acquire(blocking=False):
        raise RuntimeError('Ses islemi halen devam ediyor.')
    try:
        if VOICE_MODEL is None:
            raise RuntimeError('Once ses modelini hazirla.')
        MIC_STOP.clear()
        chunks = []
        # 8 seconds maximum. No audio is written to disk or sent to a cloud API.
        with sd.InputStream(samplerate=16000, channels=1, dtype='float32') as stream:
            for _ in range(40):
                if MIC_STOP.is_set():
                    return {'text': '', 'cancelled': True}
                data, _ = stream.read(3200)
                chunks.append(data.copy())
        if MIC_STOP.is_set():
            return {'text': '', 'cancelled': True}
        audio = np.concatenate(chunks).flatten()
        segments, _ = VOICE_MODEL.transcribe(audio, language='tr', beam_size=1, vad_filter=True, condition_on_previous_text=False)
        text = ' '.join(s.text.strip() for s in segments).strip()
        if MIC_STOP.is_set():
            return {'text': '', 'cancelled': True}
        return {'text': text}
    finally:
        VOICE_LOCK.release()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send_json(self, status, data):
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        if not TOKEN or not hmac.compare_digest(self.headers.get('X-OMNEX-Token', ''), TOKEN):
            self.send_json(403, {'error': 'Yetkisiz istek.'})
            return
        if self.headers.get('Origin'):
            self.send_json(403, {'error': 'Tarayici istekleri kabul edilmez.'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size < 0 or size > 16384:
                self.send_json(413, {'error': 'Istek cok buyuk.'})
                return
            data = json.loads(self.rfile.read(size) or b'{}')
            if not isinstance(data, dict):
                raise ValueError('Nesne gerekli.')
            if self.path == '/camera/start':
                index = data.get('index', 0)
                if type(index) is not int or not 0 <= index <= 3:
                    raise ValueError('Gecersiz kamera numarasi.')
                result = camera_start(index)
            elif self.path == '/camera/frame':
                result = frame()
            elif self.path == '/camera/stop':
                camera_stop()
                result = {'ok': True}
            elif self.path == '/voice/prepare':
                result = prepare_voice()
            elif self.path == '/voice/listen':
                result = listen()
            elif self.path == '/voice/stop':
                MIC_STOP.set()
                result = {'ok': True}
            elif self.path == '/health':
                result = {'ok': True}
            else:
                self.send_json(404, {'error': 'Bilinmeyen islem.'})
                return
            self.send_json(200, result)
        except Exception as exc:
            self.send_json(500, {'error': str(exc)[:400]})


def main():
    if len(TOKEN) < 32:
        raise SystemExit('Missing session token')
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True

    def watch_parent():
        sys.stdin.buffer.read()
        MIC_STOP.set()
        camera_stop()
        server.shutdown()

    def idle_camera():
        while True:
            time.sleep(2)
            if CAMERA is not None and time.monotonic() - LAST_FRAME > 12:
                camera_stop()

    threading.Thread(target=watch_parent, daemon=True).start()
    threading.Thread(target=idle_camera, daemon=True).start()
    print(json.dumps({'port': server.server_port}), flush=True)
    try:
        server.serve_forever()
    finally:
        camera_stop()
        server.server_close()


if __name__ == '__main__':
    main()
