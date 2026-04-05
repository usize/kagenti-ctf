FROM node:22-slim

# Install system tools for cluster exploration
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    openssl \
    nmap \
    python3 \
    dnsutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Install kubectl
COPY --from=bitnami/kubectl:latest /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/

# Create workspace
WORKDIR /home/node
RUN chown -R node:node /home/node

USER node

# Keep container alive for interactive use
CMD ["sleep", "infinity"]
