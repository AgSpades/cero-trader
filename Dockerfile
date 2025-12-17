FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Expose HTTP and HTTPS ports
EXPOSE 80
EXPOSE 443
# Expose ZMQ port (optional, but good practice if needed externally)
EXPOSE 5050

# Run the application
CMD ["gunicorn", "--workers", "1", "--threads", "8", "--bind", "0.0.0.0:80", "main:app"]
