FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openvpn \
    easy-rsa \
    python3 \
    python3-pip \
    supervisor \
    iptables \
    # debugging tools
    nano \
    vim \
    iputils-ping \
    curl \
    ca-certificates \
    openssh-client \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install Python dependencies
COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /app/backend/requirements.txt

# Copy application
COPY backend/ /app/backend/
COPY frontend/ /app/frontend/

# Download frontend vendor dependencies locally (to avoid CDN reliance at runtime)
ARG ALPINE_JS_VERSION=3.15.11
ADD https://cdn.jsdelivr.net/npm/alpinejs@${ALPINE_JS_VERSION}/dist/cdn.min.js /app/frontend/vendor/alpine.min.js
ADD https://cdn.tailwindcss.com /app/frontend/vendor/tailwind.js
COPY scripts/ /app/scripts/
COPY config/ /app/config/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Create log directory for supervisor
RUN mkdir -p /var/log/supervisor

VOLUME /data

ENV UI_PORT=80

EXPOSE 1194/udp
EXPOSE 80

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
