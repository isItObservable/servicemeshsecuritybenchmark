#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
### type: could be equal to kuma, linkerd, istio, ambientmesh, cilium, traefikmesh, or none
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
   --dtoperatortoken)
          DTOPERATORTOKEN="$2"
         shift 2
          ;;
       --dtingesttoken)
          DTTOKEN="$2"
         shift 2
          ;;
        --environment)
        ENVIRONMENT="$2"
        shift 2
        ;;
       --dtid)
          DT_TENANT_ID="$2"
         shift 2
          ;;
       --clustername)
         CLUSTERNAME="$2"
         shift 2
         ;;
       --type)
         TYPE="$2"
         shift 2
         ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"
 if [ -z "$CLUSTERNAME" ]; then
   echo "Error: clustername not set!"
   exit 1
 fi
 if [ -z "$DT_TENANT_ID" ]; then
   echo "Error: tennat id not set!"
   exit 1
 fi
 if [ -z "$ENVIRONMENT" ]; then
   ENVIRONMENT="live"
 fi

 if [ -z "$DTTOKEN" ]; then
   echo "Error: Data ingest api-token not set!"
   exit 1
 fi

 if [ -z "$DTOPERATORTOKEN" ]; then
   echo "Error: DT operator token not set!"
   exit 1
 fi
 if [ -z "$TYPE" ]; then
   echo "Error: type of test  not set!"
   exit 1
 fi


if [ "$ENVIRONMENT" == "live" ]; then
  export DYNATRACE_LIVE_URL="$DT_TENANT_ID.live.dynatrace.com"
  export DYNATRACE_APPS_URL="$DT_TENANT_ID.apps.dynatrace.com"
else
  export DYNATRACE_LIVE_URL="$DT_TENANT_ID.$ENVIRONMENT.dynatracelabs.com"
  export DYNATRACE_APPS_URL="$DT_TENANT_ID.$ENVIRONMENT.apps.dynatracelabs.com"
fi

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0-rc.2/experimental-install.yaml

#-----Installing mesh-----------------
if [  "$TYPE" = 'kuma' ]; then
  echo "installing kuma"
  helm repo add kuma https://kumahq.github.io/charts
  helm repo update
  helm install --create-namespace --namespace kuma-system kuma kuma/kuma --wait
  kubectl apply -f kuma/gatewayclass.yaml
  kubectl apply -f kuma/MeshMetric.yaml
  kubectl apply -f kuma/meshtrace.yaml
  kubectl apply -f kuma/MeshAccesslog.yaml




else
  if [  "$TYPE" = 'linkerd' ]; then

    echo "installing linkerd"
    step certificate create root.linkerd.cluster.local ca.crt ca.key \
    --profile root-ca --no-password --insecure
    step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
    --profile intermediate-ca --not-after 8760h --no-password --insecure \
    --ca ca.crt --ca-key ca.key

    # add the repo for edge releases:
    helm repo add linkerd-edge https://helm.linkerd.io/edge

    helm install linkerd-crds linkerd-edge/linkerd-crds \
      -n linkerd --create-namespace --set installGatewayAPI=false

    helm install linkerd-control-plane \
      -n linkerd \
      --devel \
      --set-file identityTrustAnchorsPEM=ca.crt \
      --set-file identity.issuer.tls.crtPEM=issuer.crt \
      --set-file identity.issuer.tls.keyPEM=issuer.key \
      linkerd-edge/linkerd-control-plane


    helm install linkerd-jaeger \
      -n linkerd \
      -f linkerd/jaeger-value.yaml \
      linkerd-edge/linkerd-jaeger

     # Install kgateway
     helm install  --create-namespace --namespace kgateway-system --version v2.1.0-main \
     kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
     --set controller.image.pullPolicy=Always

     helm install  --namespace kgateway-system --version v2.1.0-main \
     kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
     --set controller.image.pullPolicy=Always --set agentgateway.enabled=true --set waypoint.enabled=true

  else
     if [  "$TYPE" = 'ambient-kgateway' ]; then
         echo "installing ambient"
         helm repo add istio https://istio-release.storage.googleapis.com/charts
         helm repo update istio
         helm install istio-base istio/base -n istio-system --create-namespace --wait
         helm install istiod istio/istiod --namespace istio-system --set profile=ambient -f istio/ambientmesh/values.yaml --wait
         helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
         helm install ztunnel istio/ztunnel -n istio-system  --wait


         # Install kgateway
         helm install  --create-namespace --namespace kgateway-system --version v2.1.0-main \
         kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
         --set controller.image.pullPolicy=Always

         helm install  --namespace kgateway-system --version v2.1.0-main \
         kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
         --set controller.image.pullPolicy=Always --set agentgateway.enabled=true --set waypoint.enabled=true



     else

         if [  "$TYPE" = 'ambient' ]; then
           echo "installing ambient"
           helm repo add istio https://istio-release.storage.googleapis.com/charts
           helm repo update istio
           helm install istio-base istio/base -n istio-system --create-namespace --wait
           helm install istiod istio/istiod --namespace istio-system --set profile=ambient -f istio/ambientmesh/values.yaml --wait
           helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
           helm install ztunnel istio/ztunnel -n istio-system  --wait

         else
            if [  "$TYPE" = 'istio' ]; then
              echo "installing istio"
              helm repo add istio https://istio-release.storage.googleapis.com/charts
              helm repo update
              helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
              helm install istiod istio/istiod -n istio-system  -f istio/values.yaml --wait


            fi

         fi
     fi
  fi
fi



#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml




helm install dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --version 1.7.1 \
  --create-namespace --namespace dynatrace \
  --atomic

kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s,TENANTURL_TOREPLACE,$DYNATRACE_LIVE_URL," dynatrace/dynakube.yaml
    sed -i '' "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME," dynatrace/dynakube.yaml
else
    # Linux
    sed -i "s,TENANTURL_TOREPLACE,$DYNATRACE_LIVE_URL," dynatrace/dynakube.yaml
    sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME," dynatrace/dynakube.yaml
fi

### Update the ip of the ip adress for the ingres
#TODO to update this part to create the various Gateway rules

#Deploy collector
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="https://$DYNATRACE_LIVE_URL" --from-literal=clustername="$CLUSTERNAME"  --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl label namespace  default oneagent=false
kubectl apply -f opentelemetry/rbac.yaml


#deploy demo application
kubectl apply -f dynatrace/dynakube.yaml -n dynatrace
kubectl create ns booking
kubectl label namespace  booking oneagent=false
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="https://$DYNATRACE_LIVE_URL" --from-literal=dt_api_token="$DTTOKEN" -n booking


#---label namespace-----
echo "labeling demo namespace"
if [  "$TYPE" = 'kuma' ]; then
  echo " kuma"
   kubectl apply -f kuma/kuma_gateway.yaml
   kubectl label namespace booking kuma.io/sidecar-injection=enabled
   kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml
   kubectl apply -f kuma/referencegrant.yaml
   kubectl apply -f bookinfo/manifest/simpleroute.yaml

else
  if [  "$TYPE" = 'linkerd' ]; then
    kubectl apply -f linkerd/gateway.yaml
    kubectl annotate ns booking linkerd.io/inject=enabled
    kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
    kubectl apply -f linkerd/referencegrant.yaml
    kubectl apply -f linkerd/observability.yaml
    echo "🔧 Applying patch..."
    HTTP_IDX=$(kubectl get svc bookinfo-gateway -n  kgateway-system  -o json |  jq -r '.spec.ports | to_entries | .[] | select(.value.name == "listener-80") | .key')
    PATCH_OPS="[{\"op\": \"replace\", \"path\": \"/spec/ports/${HTTP_IDX}/nodePort\", \"value\": 30080}]"
    kubectl patch svc bookinfo-gateway -n  kgateway-system   --type='json'  -p="${PATCH_OPS}"

  else
     if [  "$TYPE" = 'ambient' ]; then
       echo " ambient"
       kubectl apply -f istio/gateway.yaml
       kubectl label namespace booking istio.io/dataplane-mode=ambient
       kubectl apply -f istio/ambientmesh/waypoint.yaml
       kubectl label namespace booking istio.io/use-waypoint=bookinfo-waypoint
       kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
       kubectl apply -f istio/referencegrant.yaml

       echo "🔧 Applying patch..."
       HTTP_IDX=$(kubectl get svc bookinfo-gateway-istio -n booking -o json |  jq -r '.spec.ports | to_entries | .[] | select(.value.name == "http") | .key')
       PATCH_OPS="[{\"op\": \"replace\", \"path\": \"/spec/ports/${HTTP_IDX}/nodePort\", \"value\": 30080}]"

       kubectl patch svc bookinfo-gateway-istio -n booking  --type='json'  -p="${PATCH_OPS}"

     else
        if [  "$TYPE" = 'istio' ]; then
          echo " istio"
          kubectl apply -f istio/gateway.yaml
          kubectl label namespace booking istio-injection=enabled
          kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
          kubectl apply -f istio/referencegrant.yaml
          echo "🔧 Applying patch..."
          echo "🔧 Applying patch..."
          HTTP_IDX=$(kubectl get svc bookinfo-gateway-istio -n booking -o json |  jq -r '.spec.ports | to_entries | .[] | select(.value.name == "http") | .key')
          PATCH_OPS="[{\"op\": \"replace\", \"path\": \"/spec/ports/${HTTP_IDX}/nodePort\", \"value\": 30080}]"

          kubectl patch svc bookinfo-gateway-istio -n booking  --type='json'  -p="${PATCH_OPS}"



        else
          if [  "$TYPE" = 'ambient-kgateway' ]; then
               echo " ambient-kgateway"
               kubectl apply -f kgateway-ambient/gatewayparameter.yaml
               kubectl apply -f kgateway-ambient/gateway.yaml
               kubectl label namespace booking istio.io/dataplane-mode=ambient
               kubectl apply -f kgateway-ambient/waypoint.yaml
               kubectl label namespace booking istio.io/use-waypoint=kgateway-waypoint
               kubectl apply -f kgateway-ambient/observability.yaml
               kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_kgateway.yaml
               kubectl apply -f kgateway-ambient/referencegrant.yaml
               echo "🔧 Applying patch..."
               HTTP_IDX=$(kubectl get svc bookinfo-gateway -n kgateway-system -o json |  jq -r '.spec.ports | to_entries | .[] | select(.value.name == "listener-80") | .key')
               PATCH_OPS="[{\"op\": \"replace\", \"path\": \"/spec/ports/${HTTP_IDX}/nodePort\", \"value\": 30080}]"
               kubectl patch svc bookinfo-gateway -n kgateway-system  --type='json'  -p="${PATCH_OPS}"


          else
            echo "no mesh- no annotation"
            kubectl apply -f openTelemetry-manifest_statefulset.yaml
          fi
        fi
     fi
  fi
fi


kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml
kubectl apply -f bookinfo/manifest/deploy.yaml -n booking
export SCHEDULE_TIME=$(date -u -d '+5 minutes' '+%M * * * *')
envsubst < bookinfo/manifest/loadtest.yaml | kubectl apply -n booking -f -

if [  "$TYPE" != 'none' ]; then
    if [  "$TYPE" != 'ambient-kgateway' ]; then
       kubectl apply -f kgateway-ambient/simpleroute.yaml
    else
      if [  "$TYPE" != 'linkerd' ]; then
        kubectl apply -f kgateway-ambient/simpleroute.yaml
      else
        kubectl apply -f bookinfo/manifest/simpleroute.yaml
      fi
    fi
#  kubectl apply -f opentelemetry/policy.yaml
fi
#Deploy the ingress rules
echo "--------------Demo--------------------"
echo "Installation finished "
echo "========================================================"


