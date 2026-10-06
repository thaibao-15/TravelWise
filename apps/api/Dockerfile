# ==========================================
# TravelWise API Dockerfile
# Base: Python 3.14 on Debian 12 (bookworm)
# Package Manager: uv
# ==========================================

FROM python:3.14-slim-bookworm AS base

# Environment configurations
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# Install system dependencies & Microsoft ODBC Driver for SQL Server (17 & 18)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    unixodbc \
    unixodbc-dev \
    libgssapi-krb5-2 \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list | tee /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
    msodbcsql18 \
    msodbcsql17 \
    && rm -rf /var/lib/apt/lists/*

# Install uv from official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy project manifests first to take advantage of Docker layer caching
COPY pyproject.toml uv.lock README.md ./

# Install dependencies (frozen lockfile, excluding dev tools)
RUN uv sync --frozen --no-install-project --no-dev

# Copy application source code and migration / script configs
COPY app ./app
COPY alembic ./alembic
COPY alembic.ini ./alembic.ini
COPY seed.py ./seed.py
COPY scripts ./scripts

# Install the application itself
RUN uv sync --frozen --no-dev

# Add virtual environment to PATH
ENV PATH="/app/.venv/bin:$PATH"

# Default port for FastAPI
EXPOSE 8000

# Start Uvicorn production server
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
