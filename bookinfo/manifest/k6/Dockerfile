FROM hrexed/xk6-dynatrace-output:0.11
COPY --chown=root:root ./loadtest.js ./loadtest.js
ENTRYPOINT ["k6","run","-o", "output-dynatrace" ,"./loadtest.js"]