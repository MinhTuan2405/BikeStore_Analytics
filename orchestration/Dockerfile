FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV DAGSTER_HOME=/opt/dagster/dagster_home \
    PATH="/opt/dagster/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /opt/dagster/app

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --group dev --no-install-project

COPY orchestration ./orchestration
COPY workspace.yaml ./workspace.yaml
COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN uv sync --frozen --group dev

RUN mkdir -p "${DAGSTER_HOME}"
RUN chmod +x ./docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/opt/dagster/app/docker-entrypoint.sh"]
CMD ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000", "-w", "workspace.yaml"]
