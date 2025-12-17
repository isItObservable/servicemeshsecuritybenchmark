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
       --dturl)
          DTURL="$2"
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
 if [ -z "$DTURL" ]; then
   echo "Error: Dt url not set!"
   exit 1
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

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0-rc.2/experimental-install.yaml

#-----Installing mesh-----------------
if [  "$TYPE" = 'kuma' ]; then
  echo "installing kuma"
  helm repo add kuma https://kumahq.github.io/charts
  helm repo update
  helm install --create-namespace --namespace kuma-system kuma kuma/kuma
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
         helm upgrade -i --create-namespace --namespace kgateway-system --version v2.1.0-main \
         kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
         --set controller.image.pullPolicy=Always

         helm upgrade -i --namespace kgateway-system --version v2.1.0-main \
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




helm upgrade dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --version 1.7.0 \
  --create-namespace --namespace dynatrace \
  --install \
  --atomic
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i  '' "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i  '' "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml


### Update the ip of the ip adress for the ingres
#TODO to update this part to create the various Gateway rules

#Deploy collector
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=clustername="$CLUSTERNAME"  --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl label namespace  default oneagent=false
kubectl apply -f opentelemetry/rbac.yaml


#deploy demo application
kubectl apply -f dynatrace/dynakube.yaml -n dynatrace
kubectl create ns otel-demo
kubectl label namespace  otel-demo oneagent=false


#---label namespace-----
echo "labeling demo namespace"
if [  "$TYPE" = 'kuma' ]; then
  echo " kuma"
   kubectl apply -f kuma/kuma_gateway.yaml
   kubectl label namespace otel-demo kuma.io/sidecar-injection=enabled
   kubectl apply -f openTelemetry-manifest_statefulset.yaml
   kubectl apply -f kuma/referencegrant.yaml
   kubectl apply -f opentelemetry/simpleroute.yaml

else
  if [  "$TYPE" = 'linkerd' ]; then
    kubectl apply -f linkerd/gateway.yaml
    kubectl annotate ns otel-demo linkerd.io/inject=enabled
    kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
    kubedtl apply -f linkerd/referencegrant.yaml
  else
     if [  "$TYPE" = 'ambient' ]; then
       echo " ambient"
       kubectl apply -f istio/gateway.yaml
       kubectl label namespace otel-demo istio.io/dataplane-mode=ambient
       kubectl apply -f istio/ambientmesh/waypoint.yaml
       kubectl label namespace otel-demo istio.io/use-waypoint=otel-demo-waypoint
       kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
       kubectl apply -f istio/referencegrant.yaml
     else
        if [  "$TYPE" = 'istio' ]; then
          echo " istio"
          kubectl apply -f istio/gateway.yaml
          kubectl label namespace otel-demo istio-injection=enabled
          kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
          kubectl apply -f istio/referencegrant.yaml
        else
          if [  "$TYPE" = 'ambient-kgateway' ]; then
               echo " ambient-kgateway"
               kubectl apply -f kgateway-ambient/gateway.yaml
               kubectl label namespace otel-demo istio.io/dataplane-mode=ambient
               kubectl apply -f kgateway-ambient/waypoint.yaml
               kubectl label namespace otel-demo istio.io/use-waypoint=kgateway-waypoint
               kubectl apply -f kgateway-ambient/observability.yaml
               kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_kgateway.yaml
               kubectl apply -f kgateway-ambient/referencegrant.yaml

          else
            echo "no mesh- no annotation"
            kubectl apply -f openTelemetry-manifest_statefulset.yaml
          fi
        fi
     fi
  fi
fi


kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml
kubectl apply -f opentelemetry/deploy_1_12.yaml -n otel-demo

if [  "$TYPE" != 'none' ]; then
    if [  "$TYPE" != 'ambient-kgateway' ]; then
       kubectl apply -f kgateway-ambient/simpleroute.yaml
    else
      kubectl apply -f opentelemetry/simpleroute.yaml
    fi
#  kubectl apply -f opentelemetry/policy.yaml
fi
#Deploy the ingress rules
echo "--------------Demo--------------------"
echo "Installation finished "
echo "========================================================"


