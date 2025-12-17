import zmq
import json
import logging
import threading
import sys
from flask import Flask, request, jsonify

# Configure logging to stdout
logging.basicConfig(
    filename='worker.log',
    stream=sys.stdout,
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

app = Flask(__name__)

# ZeroMQ Context and Socket Setup
context = zmq.Context()
zmq_socket = context.socket(zmq.PUSH)

# BINDING: This script is the server. 
# Your MQL5 EA must CONNECT to this address.
try:
    zmq_socket.bind("tcp://*:5050")
except zmq.ZMQError as e:
    print(f"ZMQ Bind Error: {e}")
    raise

# Create a Lock for thread safety
zmq_lock = threading.Lock()

REQUIRED_FIELDS = {"signal", "symbol", "price", "time", "interval", "volume"}

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok"}), 200   

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.json
        if not data:
            return jsonify({"error": "Invalid JSON"}), 400
        
        # Validate keys
        if not REQUIRED_FIELDS.issubset(data.keys()):
            logging.warning(f"Missing fields in payload: {data}")
            return jsonify({"error": "Missing fields"}), 400

        # Forward to ZMQ with Thread Safety
        payload_str = json.dumps(data)
        logging.info(f"Received payload: {payload_str}") # Log before sending
        
        with zmq_lock:
            zmq_socket.send_string(payload_str)
        logging.info(f"Relayed signal: {payload_str}")
        
        return jsonify({"status": "received"}), 200

    except Exception as e:
        logging.error(f"Error processing webhook: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    try:
        app.run(host='0.0.0.0', port=8080, debug=True, use_reloader=False)
    except Exception as e:
        logging.error(f"Flask Run Error: {e}")
        raise