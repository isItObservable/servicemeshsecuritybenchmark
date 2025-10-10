// Copyright Istio Authors
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.

// ============================================================================
// OpenTelemetry instrumentation - MUST be initialized BEFORE any other require
// ============================================================================
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { Resource } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } = require('@opentelemetry/semantic-conventions');
const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');

// Optional: Enable diagnostic logging for debugging
if (process.env.OTEL_LOG_LEVEL === 'debug') {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
}

// Configure OpenTelemetry SDK
const sdk = new NodeSDK({

   traceExporter: new OTLPTraceExporter({
     url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317',
   }),
   instrumentations: [
     getNodeAutoInstrumentations({
       // Customize auto-instrumentation
       '@opentelemetry/instrumentation-http': {
         ignoreIncomingRequestHook: (req) => {
           // Don't trace health checks
           return req.url === '/health';
         },
       },
       '@opentelemetry/instrumentation-mysql': {},
       '@opentelemetry/instrumentation-mongodb': {},
     }),
   ],
 });

// Start SDK
sdk.start();
console.log('OpenTelemetry instrumentation started');

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('OpenTelemetry SDK terminated'))
    .catch((error) => console.log('Error terminating OpenTelemetry SDK:', error))
    .finally(() => {
      console.log("SIGTERM received");
      server.close(() => {
        process.exit(0);
      });
    });
});

// ============================================================================
// Application code starts here
// ============================================================================
const http = require('http');
const HttpDispatcher = require('httpdispatcher');
const dispatcher = new HttpDispatcher();
const api = require('@opentelemetry/api');

// Get tracer for manual instrumentation
const tracer = api.trace.getTracer('ratings-service', '1.0.0');


const port = parseInt(process.argv[2]);

const userAddedRatings = []; // used to demonstrate POST functionality

let unavailable = false;
let healthy = true;

if (process.env.SERVICE_VERSION === 'v-unavailable') {
    // make the service unavailable once in 60 seconds
    setInterval(function () {
        unavailable = !unavailable;
    }, 60000);
}

if (process.env.SERVICE_VERSION === 'v-unhealthy') {
    // make the service unavailable once in 15 minutes for 15 minutes.
    // 15 minutes is chosen since the Kubernetes's exponential back-off is reset after 10 minutes
    // of successful execution
    // see https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy
    // Kiali shows the last 10 or 30 minutes, so to show the error rate of 50%,
    // it will be required to run the service for 30 minutes, 15 minutes of each state (healthy/unhealthy)
    setInterval(function () {
        healthy = !healthy;
        unavailable = !unavailable;
    }, 900000);
}

/**
 * We default to using mongodb, if DB_TYPE is not set to mysql.
 */
if (process.env.SERVICE_VERSION === 'v2') {
  if (process.env.DB_TYPE === 'mysql') {
    var mysql = require('mysql');
    var hostName = process.env.MYSQL_DB_HOST;
    var portNumber = process.env.MYSQL_DB_PORT;
    var username = process.env.MYSQL_DB_USER;
    var password = process.env.MYSQL_DB_PASSWORD;
  } else {
    var MongoClient = require('mongodb').MongoClient;
    var url = process.env.MONGO_DB_URL;
  }
}

dispatcher.onPost(/^\/ratings\/[0-9]*/, function (req, res) {
  const span = api.trace.getActiveSpan();
  const productIdStr = req.url.split('/').pop();
  const productId = parseInt(productIdStr);
  let ratings = {};

  if (span) {
    span.updateName('POST /ratings/:id');
    span.setAttribute('http.route', '/ratings/:id');
    span.setAttribute('product.id', productId);
  }

  if (Number.isNaN(productId)) {
    if (span) {
      span.setAttribute('error', true);
      span.setAttribute('http.status_code', 400);
    }
    res.writeHead(400, {'Content-type': 'application/json'});
    res.end(JSON.stringify({error: 'please provide numeric product ID'}));
    return;
  }

  try {
    ratings = JSON.parse(req.body);
  } catch (error) {
    if (span) {
      span.recordException(error);
      span.setAttribute('error', true);
      span.setAttribute('http.status_code', 400);
    }
    res.writeHead(400, {'Content-type': 'application/json'});
    res.end(JSON.stringify({error: 'please provide valid ratings JSON'}));
    return;
  }

  if (process.env.SERVICE_VERSION === 'v2') { // the version that is backed by a database
    if (span) {
      span.setAttribute('http.status_code', 501);
    }
    res.writeHead(501, {'Content-type': 'application/json'});
    res.end(JSON.stringify({error: 'Post not implemented for database backed ratings'}));
  } else { // the version that holds ratings in-memory
    if (span) {
      span.setAttribute('http.status_code', 200);
    }
    res.writeHead(200, {'Content-type': 'application/json'});
    res.end(JSON.stringify(putLocalReviews(productId, ratings)));
  }
});

dispatcher.onGet(/^\/ratings\/[0-9]*/, function (req, res) {
  const span = api.trace.getActiveSpan();
  const productIdStr = req.url.split('/').pop();
  const productId = parseInt(productIdStr);

  if (span) {
    span.updateName('GET /ratings/:id');
    span.setAttribute('http.route', '/ratings/:id');
    span.setAttribute('product.id', productId);
  }

  if (Number.isNaN(productId)) {
    if (span) {
      span.setAttribute('error', true);
      span.setAttribute('http.status_code', 400);
    }
    res.writeHead(400, {'Content-type': 'application/json'});
    res.end(JSON.stringify({error: 'please provide numeric product ID'}));
  } else if (process.env.SERVICE_VERSION === 'v2') {
    let firstRating = 0;
    let secondRating = 0;

    if (process.env.DB_TYPE === 'mysql') {
      if (span) {
        span.setAttribute('db.system', 'mysql');
      }

      const connection = mysql.createConnection({
        host: hostName,
        port: portNumber,
        user: username,
        password: password,
        database: 'test'
      });

      connection.connect(function(err) {
          if (err) {
              if (span) {
                span.recordException(err);
                span.setAttribute('error', true);
                span.setAttribute('http.status_code', 500);
              }
              res.end(JSON.stringify({error: 'could not connect to ratings database'}));
              console.log(err);
              return;
          }
          connection.query('SELECT Rating FROM ratings', function (err, results, fields) {
              if (err) {
                  if (span) {
                    span.recordException(err);
                    span.setAttribute('error', true);
                    span.setAttribute('http.status_code', 500);
                  }
                  res.writeHead(500, {'Content-type': 'application/json'});
                  res.end(JSON.stringify({error: 'could not perform select'}));
                  console.log(err);
              } else {
                  if (results[0]) {
                      firstRating = results[0].Rating;
                  }
                  if (results[1]) {
                      secondRating = results[1].Rating;
                  }
                  const result = {
                      id: productId,
                      ratings: {
                          Reviewer1: firstRating,
                          Reviewer2: secondRating
                      }
                  };
                  if (span) {
                    span.setAttribute('rating.reviewer1', firstRating);
                    span.setAttribute('rating.reviewer2', secondRating);
                    span.setAttribute('http.status_code', 200);
                  }
                  res.writeHead(200, {'Content-type': 'application/json'});
                  res.end(JSON.stringify(result));
              }
          });
          // close the connection
          connection.end();
      });
    } else {
      if (span) {
        span.setAttribute('db.system', 'mongodb');
      }

      MongoClient.connect(url, function (err, client) {
        if (err) {
          if (span) {
            span.recordException(err);
            span.setAttribute('error', true);
            span.setAttribute('http.status_code', 500);
          }
          res.writeHead(500, {'Content-type': 'application/json'});
          res.end(JSON.stringify({error: 'could not connect to ratings database'}));
          console.log(err);
        } else {
          const db = client.db("test");
          db.collection('ratings').find({}).toArray(function (err, data) {
            if (err) {
              if (span) {
                span.recordException(err);
                span.setAttribute('error', true);
                span.setAttribute('http.status_code', 500);
              }
              res.writeHead(500, {'Content-type': 'application/json'});
              res.end(JSON.stringify({error: 'could not load ratings from database'}));
              console.log(err);
            } else {
              if (data[0]) {
                firstRating = data[0].rating;
              }
              if (data[1]) {
                secondRating = data[1].rating;
              }
              const result = {
                id: productId,
                ratings: {
                  Reviewer1: firstRating,
                  Reviewer2: secondRating
                }
              };
              if (span) {
                span.setAttribute('rating.reviewer1', firstRating);
                span.setAttribute('rating.reviewer2', secondRating);
                span.setAttribute('http.status_code', 200);
              }
              res.writeHead(200, {'Content-type': 'application/json'});
              res.end(JSON.stringify(result));
            }
            // close client once done:
            client.close();
          });
        }
      });
    }
  } else {
      if (process.env.SERVICE_VERSION === 'v-faulty') {
        // in half of the cases return error,
        // in another half proceed as usual
        const random = Math.random(); // returns [0,1]
        if (span) {
          span.setAttribute('service.behavior', 'faulty');
          span.setAttribute('random.value', random);
        }
        if (random <= 0.5) {
          getLocalReviewsServiceUnavailable(res);
        } else {
          getLocalReviewsSuccessful(res, productId);
        }
      }
      else if (process.env.SERVICE_VERSION === 'v-delayed') {
        // in half of the cases delay for 7 seconds,
        // in another half proceed as usual
        const random = Math.random(); // returns [0,1]
        if (span) {
          span.setAttribute('service.behavior', 'delayed');
          span.setAttribute('random.value', random);
        }
        if (random <= 0.5) {
          if (span) {
            span.setAttribute('delay.seconds', 7);
          }
          setTimeout(getLocalReviewsSuccessful, 7000, res, productId);
        } else {
          getLocalReviewsSuccessful(res, productId);
        }
      }
      else if (process.env.SERVICE_VERSION === 'v-unavailable' || process.env.SERVICE_VERSION === 'v-unhealthy') {
          if (span) {
            span.setAttribute('service.behavior', process.env.SERVICE_VERSION);
            span.setAttribute('service.unavailable', unavailable);
          }
          if (unavailable) {
              getLocalReviewsServiceUnavailable(res);
          } else {
              getLocalReviewsSuccessful(res, productId);
          }
      }
      else {
        getLocalReviewsSuccessful(res, productId);
      }
  }
});

dispatcher.onGet('/health', function (req, res) {
    if (healthy) {
        res.writeHead(200, {'Content-type': 'application/json'});
        res.end(JSON.stringify({status: 'Ratings is healthy'}));
    } else {
        res.writeHead(500, {'Content-type': 'application/json'});
        res.end(JSON.stringify({status: 'Ratings is not healthy'}));
    }
});

function putLocalReviews (productId, ratings) {
  userAddedRatings[productId] = {
    id: productId,
    ratings: ratings
  };
  return getLocalReviews(productId);
}

function getLocalReviewsSuccessful(res, productId) {
  const span = api.trace.getActiveSpan();
  if (span) {
    span.setAttribute('http.status_code', 200);
  }
  res.writeHead(200, {'Content-type': 'application/json'});
  res.end(JSON.stringify(getLocalReviews(productId)));
}

function getLocalReviewsServiceUnavailable(res) {
  const span = api.trace.getActiveSpan();
  if (span) {
    span.setAttribute('error', true);
    span.setAttribute('http.status_code', 503);
  }
  res.writeHead(503, {'Content-type': 'application/json'});
  res.end(JSON.stringify({error: 'Service unavailable'}));
}

function getLocalReviews (productId) {
  if (typeof userAddedRatings[productId] !== 'undefined') {
      return userAddedRatings[productId];
  }
  return {
    id: productId,
    ratings: {
      'Reviewer1': 5,
      'Reviewer2': 4
    }
  };
}

function handleRequest (request, response) {
  try {
    console.log(request.method + ' ' + request.url);
    dispatcher.dispatch(request, response);
  } catch (err) {
    const span = api.trace.getActiveSpan();
    if (span) {
      span.recordException(err);
      span.setAttribute('error', true);
    }
    console.log(err);
  }
}

const server = http.createServer(handleRequest);

server.listen(port, function () {
  console.log('Server listening on: http://0.0.0.0:%s', port);
  console.log('OpenTelemetry enabled - exporting to:', process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317');
  console.log('Service version:', process.env.SERVICE_VERSION || 'v1');
  console.log('Database type:', process.env.DB_TYPE || 'in-memory');
});