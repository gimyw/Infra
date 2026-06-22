FROM debian:bookworm-slim

ARG TERRAFORM_VERSION=1.9.6
ARG TFLINT_VERSION=0.51.1
ARG CHECKOV_VERSION=3.2.246

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    gnupg  \
    git \
    jq \
    python3-pip \
    python3 \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
      -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip

RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
      -o /tmp/tflint.zip \
    && unzip /tmp/tflint.zip -d /usr/local/bin \
    && rm /tmp/tflint.zip 

RUN python3 -m venv /opt/checkov \
    && /opt/checkov/bin/pip install --no-cache-dir checkov==${CHECKOV_VERSION} \
    && /opt/checkov/bin/pip install --no-cache-dir \
       "setuptools>=78.1.1" \
       "urllib3>=2.7.0" \
    && ln -s /opt/checkov/bin/checkov /usr/local/bin/checkov

RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

RUN terraform version \
    && tflint --version \
    && checkov --version \
    && aws --version \
    && gh --version \
    && jq --version

WORKDIR /workspace