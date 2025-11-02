# subweb/app.py
from flask import Flask
from flask_socketio import SocketIO, send
import logging

logging.basicConfig(level=logging.DEBUG)
app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*", path="/subweb/socket.io", logger=True, engineio_logger=True)

@app.route("/subweb")
def index():
    return "Hello from Sub Web"

@socketio.on('message', namespace='/')
def handle(msg):
    send(f"Echo: {msg}")

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=80)


