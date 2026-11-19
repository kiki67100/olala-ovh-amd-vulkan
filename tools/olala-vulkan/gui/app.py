#!/usr/bin/env python3
"""Copie Windows de ~/olala/gui/app.py : même interface, mais llama-server Vulkan (RX 6600).
GUI sur http://localhost:7861, llama-server sur 127.0.0.1:8081. L'original (7860/8080) n'est pas touché."""
import http.client, json, os, signal, subprocess, sys, threading, time, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = r"C:\olala\llama.cpp-olala-vulkan\build-vk\bin\llama-server.exe"
# nom -> (fichier, options de placement). q5 tient entièrement en VRAM (8 Go) ;
# q8 (6,9 Go) non : --fit place automatiquement une partie des experts MoE sur le CPU.
MODELS = {
    "q5_k_m": (r"C:\olala\models\Olala-v1.0-mini-7A1B-q5_k_m.gguf", ["-ngl", "99"]),
    "q8_0-safe2": (r"C:\olala\models\Olala-v1.0-mini-7A1B-q8_0-safe2.gguf", ["-fit", "on", "-t", "6"]),
}
LLAMA_PORT, GUI_PORT = 8081, 7861
CTX = int(os.environ.get("OLALA_CTX", "32768"))
LOG = os.path.join(HERE, "llama-server.log")

state = {"model": None, "status": "stopped", "proc": None}
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
    for _ in range(600):
        if state["proc"].poll() is not None:
            state["status"] = "error (voir C:\\olala\\gui-vulkan\\llama-server.log)"
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


def main():
    first = next((a for a in sys.argv[1:] if a in MODELS), "q5_k_m")
    srv = ThreadingHTTPServer(("127.0.0.1", GUI_PORT), H)  # échoue avant de lancer le modèle si 7861 est pris
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
