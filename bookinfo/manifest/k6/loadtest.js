import http from 'k6/http';
import { Httpx } from 'https://jslib.k6.io/httpx/0.0.4/index.js';
//import tracing, { Http } from 'k6/x/tracing';
import { sleep,check} from 'k6';
import { Counter } from "k6/metrics";

/**
 * Hipster workload generator by k6
 * @param __ENV.FRONTEND_ADDR, __ENV.OTLP_SERVICE_ADDR, __ENV.OTLP_SERVICE_PORT
 * @constructor hrexed
 */

let errors = new Counter("errors");

export let options = {
    discardResponseBodies: true,

      stages: [
        { target: 100, duration: '10m' },
        { target: 200, duration: '10m' },
        { target: 250, duration: '10m' },
        { target: 350, duration: '10m' },
      ],

};
const baseurl = `http://${__ENV.FRONTEND_ADDR}`;



const tasks = {

    "productpage": 2,
     "loging": 1,
    "productpage-user": 4,
    "browseProduct" : 5,
    "logout": 1
}


const waittime = [1,2,3,4,5,6,7,8,9,10]

const products = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8','9','10'];

/*export function setup() {
  console.log(`Running xk6-distributed-tracing v${tracing.version}`);
}*/
export default function() {

    const session = new Httpx({
      baseURL: baseurl,
      timeout: 20000, // 20s timeout.
    });

   /* const http = new Http({
        exporter: "otlp",
        propagator: "w3c",
        endpoint: url
      });*/



    //Access setCurrency page
    for ( let i=0; i<tasks["productpage"]; i++)
    {
         let res = session.get(`/productpage`);
         let checkRes = check(res, { "status is 200": (r) => r.status === 200 });


        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
    }

    //Access browseProduct page
    for ( let i=0; i<tasks["login"]; i++)
    {
        let res = session.post(`/login`,{
                                                    'username': 'test',
                                                    'passwd': '123445',

                                                },{
                                                        headers: { 'Content-Type': 'multipart/form-data'},
                                                        });

        sleep(waittime[Math.floor(Math.random() * waittime.length)])
    }
     for ( let i=0; i<tasks["productpage-user"]; i++)
        {
             let res = session.get(`/productpage?u=test`);
             let checkRes = check(res, { "status is 200": (r) => r.status === 200 });


            // show the error per second in grafana
            if (checkRes === false ){
                errors.add(1);
            }
            sleep(waittime[Math.floor(Math.random() * waittime.length)])
        }

    //Access browseProduct page
    for ( let i=0; i<tasks["browseProduct"]; i++)
    {
        let product = products[Math.floor(Math.random() * products.length)]
        let res = session.get(`/api/v1/products/${product}`);
        let checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
        res = session.get(`/api/v1/products/${product}/reviews`);
        checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
        res = session.get(`/api/v1/products/${product}/ratings`);
        checkRes = check(res, { "status is 200": (r) => r.status === 200 });

       // show the error per second in grafana
       if (checkRes === false ){
           errors.add(1);
       }
       sleep(waittime[Math.floor(Math.random() * waittime.length)])

    }
    //Access addToCart page
    for ( let i=0; i<tasks["logout"]; i++)
    {
        let product = products[Math.floor(Math.random() * products.length)]
        let res = session.get(`/logout`);
        let checkRes = check(res, { "status is 302": (r) => r.status === `302` });


        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])

    }


}
export function teardown(){
  // Cleanly shutdown and flush telemetry when k6 exits.
  tracing.shutdown();
}
