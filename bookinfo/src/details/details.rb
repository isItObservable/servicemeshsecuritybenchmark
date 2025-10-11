#!/usr/bin/env ruby
# Copyright Istio Authors

require 'webrick'
require 'json'

puts "Loading OpenTelemetry..."
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/propagator/b3'
# Configure OpenTelemetry explicitly
exporter_endpoint = ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] || 'http://otel-collector.default.svc.cluster.local:4317'
service_name = ENV['OTEL_SERVICE_NAME'] || 'details'
service_version = ENV['SERVICE_VERSION'] || 'v1'

puts "Configuring OpenTelemetry to: #{exporter_endpoint}"

begin
  puts "→ Starting OpenTelemetry SDK configuration..."


  OpenTelemetry::SDK.configure do |c|
    puts "→ Inside OpenTelemetry configuration block"
    c.service_name = service_name
    c.service_version = service_version
    c.use_all()
  end

  puts "✓ OpenTelemetry configured: #{OpenTelemetry.tracer_provider.class.name}"
rescue => e
  puts "⚠️ OpenTelemetry configuration failed: #{e.class} - #{e.message}"
  puts e.backtrace.join("\n")
end

# Helper functions
def normalize_header_value(value)
  case value
  when Array then value.first.to_s
  when WEBrick::HTTPUtils::SplitHeader then value.to_s
  else value.to_s
  end
rescue
  value.to_s
end

def extract_context(request)
  carrier = {}
  request.each do |key, value|
    if key.start_with?('HTTP_')
      header_name = key.sub('HTTP_', '').downcase.tr('_', '-')
      carrier[header_name] = normalize_header_value(value)
    end
  end

  begin
    OpenTelemetry.propagation.extract(carrier)
  rescue => e
    puts "Context extraction failed: #{e.message}"
    OpenTelemetry::Context.current
  end
end

# Get port
if ARGV.length < 1
  puts "usage: #{$PROGRAM_NAME} port"
  exit(-1)
end

port = Integer(ARGV[0])
server = WEBrick::HTTPServer.new(Port: port)

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }

# Health endpoint
server.mount_proc('/health') do |req, res|
  res.status = 200
  res['Content-Type'] = 'application/json'
  res.body = JSON.generate(status: 'healthy')
end

# Details endpoint
server.mount_proc('/details') do |req, res|
  tracer = OpenTelemetry.tracer_provider.tracer('details-service')
  parent_context = extract_context(req)

  OpenTelemetry::Context.with_current(parent_context) do
    span = tracer.start_span(
      'GET /details',
      kind: :server,
      attributes: {
        'http.method' => req.request_method,
        'http.route' => '/details',
        'http.target' => req.path
      }
    )

    OpenTelemetry::Trace.with_span(span) do
      begin
        product_id = req.path.split('/').last || '0'
        span.set_attribute('product.id', product_id)

        details = {
          id: product_id.to_i,
          author: 'William Shakespeare',
          year: 1595,
          type: 'paperback',
          pages: 200,
          publisher: 'PublisherA',
          language: 'English',
          ISBN_10: '1234567890',
          ISBN_13: '123-1234567890'
        }

        span.set_attribute('http.status_code', 200)
        span.status = OpenTelemetry::Trace::Status.ok

        res.status = 200
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate(details)

        puts "✓ Span created with trace_id=#{span.context.hex_trace_id} span_id=#{span.context.hex_span_id}"

      rescue => e
        span.record_exception(e)
        span.status = OpenTelemetry::Trace::Status.error(e.message)
        span.set_attribute('http.status_code', 500)

        res.status = 500
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate(error: e.message)

        puts "⚠️ Error in /details: #{e.class} - #{e.message}"
        puts e.backtrace.join("\n")
      ensure
        span.finish
      end
    end
  end
end

puts "=" * 60
puts "Details service starting on port #{port}"
puts "Service: #{service_name} (#{service_version})"
puts "=" * 60

server.start

at_exit do
  puts "\nFlushing spans..."
  OpenTelemetry.tracer_provider.shutdown
end