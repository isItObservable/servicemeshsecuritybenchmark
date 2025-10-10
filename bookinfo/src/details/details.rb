#!/usr/bin/ruby
#
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

require 'webrick'
require 'json'
require 'net/http'

# OpenTelemetry Instrumentation
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'details')
  c.service_version = ENV.fetch('SERVICE_VERSION', 'v1')

  # Use OTLP exporter (gRPC by default)
  c.use_all() # This will auto-instrument Net::HTTP and other common libraries
end

if ARGV.length < 1 then
    puts "usage: #{$PROGRAM_NAME} port"
    exit(-1)
end

port = Integer(ARGV[0])

# Get tracer
tracer = OpenTelemetry.tracer_provider.tracer('details-service', '1.0')

server = WEBrick::HTTPServer.new(
    :BindAddress => '*',
    :Port => port,
    :AcceptCallback => -> (s) { s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) },
)

trap 'INT' do server.shutdown end

server.mount_proc '/health' do |req, res|
    res.status = 200
    res.body = {'status' => 'Details is healthy'}.to_json
    res['Content-Type'] = 'application/json'
end

server.mount_proc '/details' do |req, res|
    # Extract trace context from incoming headers
    parent_context = OpenTelemetry.propagation.extract(
        req.header,
        getter: OpenTelemetry::Context::Propagation.text_map_getter
    )

    # Start a new span with the extracted context as parent
    OpenTelemetry::Context.with_current(parent_context) do
        tracer.in_span('GET /details/:id',
                       attributes: {
                         'http.method' => req.request_method,
                         'http.url' => req.path,
                         'http.target' => req.path
                       }) do |span|

            pathParts = req.path.split('/')
            headers = get_forward_headers(req)

            begin
                begin
                  id = Integer(pathParts[-1])
                  span.set_attribute('book.id', id)
                rescue => error
                  span.record_exception(error)
                  span.set_attribute('error', true)
                  raise 'please provide numeric product id'
                end

                details = get_book_details(id, headers, tracer, span)
                res.body = details.to_json
                res['Content-Type'] = 'application/json'
                span.set_attribute('http.status_code', 200)

            rescue => error
                span.record_exception(error)
                span.set_attribute('error', true)
                span.set_attribute('http.status_code', 400)
                res.body = {'error' => error.to_s}.to_json
                res['Content-Type'] = 'application/json'
                res.status = 400
            end
        end
    end
end

# TODO: provide details on different books.
def get_book_details(id, headers, tracer, parent_span)
    if ENV['ENABLE_EXTERNAL_BOOK_SERVICE'] === 'true' then
        # the ISBN of one of Comedy of Errors on the Amazon
        # that has Shakespeare as the single author
        isbn = '0486424618'
        return fetch_details_from_external_service(isbn, id, headers, tracer)
    end

    return {
        'id' => id,
        'author': 'William Shakespeare',
        'year': 1595,
        'type' => 'paperback',
        'pages' => 200,
        'publisher' => 'PublisherA',
        'language' => 'English',
        'ISBN-10' => '1234567890',
        'ISBN-13' => '123-1234567890'
    }
end

def fetch_details_from_external_service(isbn, id, headers, tracer)
    tracer.in_span('fetch_external_book_details',
                   attributes: {
                     'book.isbn' => isbn,
                     'book.id' => id
                   }) do |span|

        uri = URI.parse('https://www.googleapis.com/books/v1/volumes?q=isbn:' + isbn)
        http = Net::HTTP.new(uri.host, ENV['DO_NOT_ENCRYPT'] === 'true' ? 80:443)
        http.read_timeout = 5 # seconds

        # DO_NOT_ENCRYPT is used to configure the details service to use either
        # HTTP (true) or HTTPS (false, default) when calling the external service to
        # retrieve the book information.
        #
        # Unless this environment variable is set to true, the app will use TLS (HTTPS)
        # to access external services.
        if ENV['DO_NOT_ENCRYPT'] != 'true' then
            http.use_ssl = true
        end

        span.set_attribute('http.url', uri.to_s)
        span.set_attribute('peer.service', 'googleapis.com')

        request = Net::HTTP::Get.new(uri.request_uri)
        request['User-Agent'] = 'Ruby'

        # Inject trace context into outgoing request
        OpenTelemetry.propagation.inject(request)

        response = http.request(request)

        span.set_attribute('http.status_code', response.code.to_i)

        if response.code.to_i != 200
            span.set_attribute('error', true)
            return {'error' => 'Sorry, product details are currently unavailable for this book.'}
        end

        json = JSON.parse(response.body)
        book = json['items'][0]['volumeInfo']

        language = book['language']
        type = book['printType'] === 'BOOK' ? 'paperback' : 'unknown'
        isbn10 = get_isbn(book, 'ISBN_10')
        isbn13 = get_isbn(book, 'ISBN_13')

        return {
            'id' => id,
            'author': book['authors'][0],
            'year': book['publishedDate'],
            'type' => type,
            'pages' => book['pageCount'],
            'publisher' => book['publisher'],
            'language' => language,
            'ISBN-10' => isbn10,
            'ISBN-13' => isbn13
        }
    end
end

def get_isbn(book, isbn_type)
  isbn_identifiers = book['industryIdentifiers'].select do |identifier|
    identifier['type'] === isbn_type
  end

  return isbn_identifiers[0]['identifier']
end

def get_forward_headers(request)
  headers = {}

  # Keep this in sync with the headers in productpage and reviews.
  incoming_headers = [
      # All applications should propagate x-request-id. This header is
      # included in access log statements and is used for consistent trace
      # sampling and log sampling decisions in Istio.
      'x-request-id',

      # Lightstep tracing header. Propagate this if you use lightstep tracing
      # in Istio (see
      # https://istio.io/latest/docs/tasks/observability/distributed-tracing/lightstep/)
      # Note: this should probably be changed to use B3 or W3C TRACE_CONTEXT.
      # Lightstep recommends using B3 or TRACE_CONTEXT and most application
      # libraries from lightstep do not support x-ot-span-context.
      'x-ot-span-context',

      # Datadog tracing header. Propagate these headers if you use Datadog
      # tracing.
      'x-datadog-trace-id',
      'x-datadog-parent-id',
      'x-datadog-sampling-priority',

      # W3C Trace Context. Compatible with OpenCensusAgent and Stackdriver Istio
      # configurations.
      'traceparent',
      'tracestate',

      # Cloud trace context. Compatible with OpenCensusAgent and Stackdriver Istio
      # configurations.
      'x-cloud-trace-context',

      # Grpc binary trace context. Compatible with OpenCensusAgent nad
      # Stackdriver Istio configurations.
      'grpc-trace-bin',

      # b3 trace headers. Compatible with Zipkin, OpenCensusAgent, and
      # Stackdriver Istio configurations.
      'x-b3-traceid',
      'x-b3-spanid',
      'x-b3-parentspanid',
      'x-b3-sampled',
      'x-b3-flags',

      # SkyWalking trace headers.
      'sw8',

      # Application-specific headers to forward.
      'end-user',
      'user-agent',

      # Context and session specific headers
      'cookie',
      'authorization',
      'jwt'
  ]

  request.each do |header, value|
    if incoming_headers.include? header then
      headers[header] = value
    end
  end

  return headers
end

server.start