# Copyright Istio Authors
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

FROM gradle:8.13.0-jdk8 AS builder


# Not sure why but we need root to build. Ignore lint error, this is for a multistage builder so it doesn't matter.
# hadolint ignore=DL3002
USER 0
COPY . /home/gradle

RUN gradle build

FROM open-liberty:24.0.0.12-kernel-slim-java17-openj9

ENV SERVERDIRNAME=reviews
# Download OpenTelemetry Java Agent
ARG OTEL_AGENT_VERSION=2.10.0
USER 0
RUN curl -L -o /opt/opentelemetry-javaagent.jar \
    https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar && \
    chmod 644 /opt/opentelemetry-javaagent.jar && \
    chown 1001:0 /opt/opentelemetry-javaagent.jar


COPY --from=builder /home/gradle/reviews-wlpcfg/servers/LibertyProjectServer/ /opt/ol/wlp/usr/servers/defaultServer/
# Not sure why but we need root to build, but without it buildx cannot get network connectivity. We swap to 1001 later.
# hadolint ignore=DL3002
USER 0
RUN /opt/ol/wlp/bin/featureUtility installServerFeatures  --acceptLicense /opt/ol/wlp/usr/servers/defaultServer/server.xml --verbose && \
    chmod -R g=rwx /opt/ol/wlp/output/defaultServer/
USER 1001

# Configure OpenTelemetry Java Agent via jvm.options
RUN echo "-javaagent:/opt/opentelemetry-javaagent.jar" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "# OpenTelemetry Configuration" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "-Dotel.service.name=reviews" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "-Dotel.traces.exporter=otlp" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "-Dotel.metrics.exporter=none" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "-Dotel.logs.exporter=none" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "-Dotel.exporter.otlp.protocol=grpc" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    echo "-Dotel.propagators=tracecontext,baggage,b3,b3multi" >> /opt/ol/wlp/usr/servers/defaultServer/jvm.options && \
    chmod 644 /opt/ol/wlp/usr/servers/defaultServer/jvm.options


ARG service_version
ARG enable_ratings
ARG star_color
ENV SERVICE_VERSION=${service_version:-v1}
ENV ENABLE_RATINGS=${enable_ratings:-false}
ENV STAR_COLOR=${star_color:-black}

# OpenTelemetry runtime configuration (can be overridden)
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
ENV OTEL_RESOURCE_ATTRIBUTES=service.namespace=bookinfo

CMD ["/opt/ol/wlp/bin/server", "run", "defaultServer"]
