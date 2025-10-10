FROM ruby:3.2-slim AS builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/microservices

# Copy Gemfile first for better caching
COPY Gemfile* ./

# Install Ruby gems
RUN gem install bundler && \
    bundle install --jobs 4 --retry 3

# Final stage
FROM ruby:3.2-slim

# Install runtime dependencies only
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/microservices

# Copy gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY details.rb .

# Create non-root user
RUN groupadd -r details && useradd -r -g details details && \
    chown -R details:details /opt/microservices

USER details

ARG service_version
ARG enable_external_book_service
ENV SERVICE_VERSION ${service_version:-v1}
ENV ENABLE_EXTERNAL_BOOK_SERVICE ${enable_external_book_service:-false}

# OpenTelemetry environment variables (can be overridden at runtime)
ENV OTEL_SERVICE_NAME=details
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=none
ENV OTEL_LOGS_EXPORTER=none

EXPOSE 9080

CMD ["ruby", "details.rb", "9080"]