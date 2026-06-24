# gitops 검증 에이전트 — helm template → kubeconform → conftest.
# AWS 권한 0(렌더·스키마·정책 검증만, 클러스터/AWS 미접근). tf-agent와 동일 베이스(debian:bookworm-slim).
FROM debian:bookworm-slim

ARG HELM_VERSION=3.16.3
ARG KUBECONFORM_VERSION=0.6.7
ARG CONFTEST_VERSION=0.56.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    tar \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# helm (정적 Go 바이너리)
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz \
    && tar -xzf /tmp/helm.tgz -C /tmp linux-amd64/helm \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tgz /tmp/linux-amd64

# kubeconform — K8s + CRD 스키마 검증
RUN curl -fsSL "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" -o /tmp/kc.tgz \
    && tar -xzf /tmp/kc.tgz -C /usr/local/bin kubeconform \
    && rm /tmp/kc.tgz

# conftest — OPA/rego 정책 검증
RUN curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" -o /tmp/ct.tgz \
    && tar -xzf /tmp/ct.tgz -C /usr/local/bin conftest \
    && rm /tmp/ct.tgz

# 설치 검증(빌드 시 깨지면 즉시 실패)
RUN helm version --short && kubeconform -v && conftest --version
