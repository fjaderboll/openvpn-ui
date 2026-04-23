FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openvpn \
    easy-rsa \
    python3 \
    python3-pip \
    python3-venv \
    supervisor \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install Python dependencies
COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /app/backend/requirements.txt

# Copy application
COPY backend/ /app/backend/
COPY frontend/ /app/frontend/
COPY scripts/ /app/scripts/
COPY config/ /app/config/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Create log directory for supervisor
RUN mkdir -p /var/log/supervisor

VOLUME /data

EXPOSE 1194/udp
EXPOSE 80

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
