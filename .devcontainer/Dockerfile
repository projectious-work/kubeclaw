
FROM debian:trixie-slim

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    locales \
    curl \
    wget \
    git \
    apt-transport-https \
    ca-certificates \
    gnupg \
    jq \
    ansible \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
RUN locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install code assistants
ENV PATH="/root/.local/bin:${PATH}"
RUN    curl -fsSL https://claude.ai/install.sh | bash \
    && curl -fsSL https://mistral.ai/vibe/install.sh | bash \
    && curl -fsSL https://opencode.ai/install | bash
    

# Install opentofu
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://get.opentofu.org/opentofu.gpg | tee /etc/apt/keyrings/opentofu.gpg >/dev/null \
    && curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null \
    && chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" | tee /etc/apt/sources.list.d/opentofu.list > /dev/null \
    && chmod a+r /etc/apt/sources.list.d/opentofu.list \
    && apt-get update \
    && apt-get install -y tofu \
    && rm -rf /var/lib/apt/lists/*

# Install Ansible collections
RUN ansible-galaxy collection install ansible.posix

# Install cloudflared (for SSH ProxyCommand via Cloudflare Tunnel)
RUN curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list \
    && apt-get update \
    && apt-get install -y cloudflared \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspaces
