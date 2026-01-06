from server import app  # Assuming your Flask app is in server.py
from waitress import serve

if __name__ == '__main__':
    serve(app, host='0.0.0.0', port=8080)