#!/usr/bin/env python3
"""Copie Windows de ~/olala/gui/app.py : même interface, mais llama-server Vulkan (RX 6600).
GUI sur http://localhost:7861, llama-server sur 127.0.0.1:8081. L'original (7860/8080) n'est pas touché."""
import http.client, json, os, signal, subprocess, sys, threading, time, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
# Dossier Windows de travail (même convention que config.sh) : surcharger avec OLALA_WIN_ROOT.
WIN_ROOT = os.environ.get("OLALA_WIN_ROOT", r"C:\olala")
BIN = os.environ.get("OLALA_LLAMA_SERVER",
                     os.path.join(WIN_ROOT, "llama.cpp-olala-vulkan", "build-vk", "bin", "llama-server.exe"))
MODELS_DIR = os.environ.get("OLALA_MODELS_DIR", os.path.join(WIN_ROOT, "models"))
# nom -> (fichier, options de placement). q5 tient entièrement en VRAM (8 Go) ;
# q8 (6,9 Go) non : --fit place automatiquement une partie des experts MoE sur le CPU.
MODELS = {
    "q5_k_m": (os.path.join(MODELS_DIR, "Olala-v1.0-mini-7A1B-q5_k_m.gguf"), ["-ngl", "99"]),
    "q8_0-safe2": (os.path.join(MODELS_DIR, "Olala-v1.0-mini-7A1B-q8_0-safe2.gguf"), ["-fit", "on", "-t", "6"]),
}
LLAMA_PORT, GUI_PORT = 8081, 7861
CTX = int(os.environ.get("OLALA_CTX", "32768"))
LOG = os.path.join(HERE, "llama-server.log")

state = {"model": None, "status": "stopped", "proc": None}


def _kill_on_close_job():
    """Job Object Windows « kill on close » : llama-server meurt avec ce processus Python,
    même si la fenêtre est fermée ou le processus tué (pas de serveur orphelin en VRAM)."""
    if os.name != "nt":
        return None
    import ctypes
    from ctypes import wintypes
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateJobObjectW.restype = wintypes.HANDLE
    k32.OpenProcess.restype = wintypes.HANDLE

    class BASIC(ctypes.Structure):
        _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64), ("PerJobUserTimeLimit", ctypes.c_int64),
                    ("LimitFlags", wintypes.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                    ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                    ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD),
                    ("SchedulingClass", wintypes.DWORD)]

    class IO(ctypes.Structure):
        _fields_ = [(n, ctypes.c_uint64) for n in ("r", "w", "o", "rt", "wt", "ot")]

    class EXT(ctypes.Structure):
        _fields_ = [("Basic", BASIC), ("Io", IO), ("ProcessMemoryLimit", ctypes.c_size_t),
                    ("JobMemoryLimit", ctypes.c_size_t), ("PeakProcessMemoryUsed", ctypes.c_size_t),
                    ("PeakJobMemoryUsed", ctypes.c_size_t)]

    job = k32.CreateJobObjectW(None, None)
    info = EXT()
    info.Basic.LimitFlags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not job or not k32.SetInformationJobObject(job, 9, ctypes.byref(info), ctypes.sizeof(info)):
        return None

    def assign(pid):
        h = k32.OpenProcess(0x0101, False, pid)  # PROCESS_SET_QUOTA | PROCESS_TERMINATE
        if h:
            k32.AssignProcessToJobObject(job, h)
            k32.CloseHandle(h)
    return assign


_job_assign = _kill_on_close_job()
lock = threading.Lock()


def healthy():
    try:
        c = http.client.HTTPConnection("127.0.0.1", LLAMA_PORT, timeout=2)
        c.request("GET", "/health")
        return c.getresponse().status == 200
    except OSError:
        return False


def stop_proc(p, wait=15):
    if p and p.poll() is None:
        p.terminate()
        try:
            p.wait(wait)
        except subprocess.TimeoutExpired:
            p.kill()


def start_model(name):
    with lock:
        stop_proc(state["proc"])
        for _ in range(20):
            if not healthy():
                break
            time.sleep(0.5)
        else:
            state.update(model=name, status="error: port 8081 déjà pris par un autre llama-server")
            return
        state.update(model=name, status="loading")
        path, placement = MODELS[name]
        cmd = [BIN, "-m", path, *placement, "-fa", "on",
               "-ctk", "q8_0", "-ctv", "q8_0", "-c", str(CTX), "-np", "1", "--cache-reuse", "256",
               "--host", "127.0.0.1", "--port", str(LLAMA_PORT)]
        state["proc"] = subprocess.Popen(cmd, stdout=open(LOG, "w", encoding="utf-8"),
                                         stderr=subprocess.STDOUT,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
        if _job_assign:
            _job_assign(state["proc"].pid)
    for _ in range(600):
        if state["proc"].poll() is not None:
            state["status"] = f"error (voir {LOG})"
            return
        if healthy() and state["proc"].poll() is None:
            state["status"] = "ready"
            return
        time.sleep(0.5)
    state["status"] = "error (timeout)"


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def send_json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            b = open(os.path.join(HERE, "index.html"), "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
        elif self.path == "/api/state":
            self.send_json({"model": state["model"], "status": state["status"],
                            "models": list(MODELS), "ctx": CTX})
        else:
            self.send_error(404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/api/model":
            name = json.loads(body).get("model")
            if name not in MODELS:
                return self.send_json({"error": "modèle inconnu"}, 400)
            if name != state["model"] or state["status"] != "ready":
                threading.Thread(target=start_model, args=(name,), daemon=True).start()
                state["status"] = "loading"
            return self.send_json({"ok": True})
        if self.path == "/v1/chat/completions":
            if state["status"] != "ready":
                return self.send_json({"error": "modèle pas prêt"}, 503)
            c = http.client.HTTPConnection("127.0.0.1", LLAMA_PORT, timeout=3600)
            c.request("POST", self.path, body, {"Content-Type": "application/json"})
            r = c.getresponse()
            self.send_response(r.status)
            self.send_header("Content-Type", r.getheader("Content-Type", "text/event-stream"))
            self.end_headers()
            try:
                while True:
                    chunk = r.read1(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass  # bouton Stop : on coupe, llama-server arrête la génération
            finally:
                c.close()
            return
        self.send_error(404)


class Server(ThreadingHTTPServer):
    # Sous Windows, SO_REUSEADDR permettrait de se lier à un port déjà pris : on l'enlève.
    allow_reuse_address = os.name != "nt"
    daemon_threads = True


def main():
    first = next((a for a in sys.argv[1:] if a in MODELS), "q5_k_m")
    try:
        srv = Server(("127.0.0.1", GUI_PORT), H)
    except OSError:  # déjà lancé : on ouvre juste la page
        print(f"Olala GUI Vulkan tourne déjà : http://localhost:{GUI_PORT}")
        webbrowser.open(f"http://localhost:{GUI_PORT}")
        return
    threading.Thread(target=start_model, args=(first,), daemon=True).start()
    print(f"Olala GUI Vulkan : http://localhost:{GUI_PORT}  (Ctrl+C pour quitter)", flush=True)
    if "--open" in sys.argv:
        webbrowser.open(f"http://localhost:{GUI_PORT}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print("Arrêt du serveur Vulkan…", flush=True)
        stop_proc(state["proc"], 10)


if __name__ == "__main__":
    main()
