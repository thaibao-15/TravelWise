# ==========================================
# TravelWise Voice Agent Dockerfile
# Base: Python 3.12 on Debian 12 (bookworm)
# Package Manager: uv
# Role: LiveKit Realtime Voice Agent Worker
# ==========================================

FROM python:3.12-slim-bookworm AS base

# Environment configurations
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# Install system dependencies (build-essential, curl for health checks if needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv from official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy dependency manifests first to leverage Docker layer caching
COPY pyproject.toml uv.lock README.md ./

# Install dependencies (frozen lockfile)
RUN uv sync --frozen --no-install-project

# Copy source code
COPY . .

# Install project into virtualenv
RUN uv sync --frozen

# Default production command: run agent in worker mode
# (LiveKit agents use 'start' for production daemon, 'dev' for local testing)
CMD ["uv", "run", "python", "main.py", "start"]
