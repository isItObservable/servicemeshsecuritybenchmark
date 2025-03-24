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


#-----Installing mesh-----------------
if [  "$TYPE" = 'kuma' ]; then
  echo "installing kuma"
  helm repo add kuma https://kumahq.github.io/charts
  helm repo update
  helm install --create-namespace --namespace kuma-system kuma kuma/kuma



  GATEWAYNAME="kuma"
else
  if [  "$TYPE" = 'linkerd' ]; then

    echo "installing linkerd"
    linkerd install --crds | kubectl apply -f -
    linkerd install | kubectl apply -f -
    linkerd jaeger install --set webhook.collectorTraceProtocol=opentelemetry | kubectl apply -f
    linkerd viz install | kubectl apply -f -
    kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN" -n linkerd-jaeger
    kubectl apply -f linkerd/linkerd-collector.yaml
    kubectl apply -f linkerd/collector_deployment.yaml
    GATEWAYNAME="linkerd"
  else
     if [  "$TYPE" = 'traefik' ]; then
       echo "installing TraefikMesh"
       helm repo add traefik https://traefik.github.io/charts
       helm repo update
       helm install traefik-mesh traefik/traefik-mesh --set kubedns=false --set controller.image.pullPolicy=IfNotPresent --set controller.image.tag=latest
       GATEWAYNAME="traefik"
     else
        if [  "$TYPE" = 'cilium' ]; then
          echo "installing Cilium"

          kubectl apply -f cilium/agentsvc.yaml
          helm repo add gadget https://inspektor-gadget.github.io/charts
          helm install gadget gadget/gadget --namespace=gadget --create-namespace -f inspecktor-gadget/values.yaml
          kubectl apply -f inspecktor-gadget/configmap.yaml -n gadget
          kubectl rollout restart ds gadget -n gadget
          kubectl apply -f inspecktor-gadget/gadget_top.yaml -n gadget
          GATEWAYNAME="cilium"
        else
           if [  "$TYPE" = 'ambient' ]; then
             echo "installing ambient"
             helm repo add istio https://istio-release.storage.googleapis.com/charts
             helm repo update istio
             helm install istio-base istio/base -n istio-system --create-namespace --wait
             helm install istiod istio/istiod --namespace istio-system --set profile=ambient-f istio/values.yaml --wait
             helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
             helm install ztunnel istio/ztunnel -n istio-system --wait

           else
            if [  "$TYPE" = 'istio' ]; then
              echo "installing istio"
              helm repo add istio https://istio-release.storage.googleapis.com/charts
              helm repo update
              helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
              helm install istiod istio/istiod -n istio-system  -f istio/values.yaml --wait
              GATEWAYNAME="istio"
            else
              #no mesh
              echo "no Mesh deployed"
            fi

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




### Deploy the Dynatrace Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.4.0/kubernetes.yaml
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.4.0/kubernetes.yaml
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i  '' "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i  '' "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml
sed -i  '' "s,CLASSNAME_REPLACE,$GATEWAYNAME,"  gateway_api/gateway.yaml

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

#deploy demo application
echo "Deploying hipster-shop"
kubectl create ns hipster-shop
kubectl label namespace hipster-shop oneagent=true
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN" -n hipster-shop

#---label namespace-----
echo "labeling demo namespace"
if [  "$TYPE" = 'kuma' ]; then
  echo " kuma"
   kubectl apply -f kuma/Mesh.yaml
   kubect apply -f  kuma/gatewayclass.yaml
   kubectl apply -f kuma/MeshMetric.yaml
   kubectl apply -f kuma/MeshAccesslog.yaml
   kubectl apply -f kuma/meshtrace.yaml
   kubectl label namespace otel-demo kuma.io/sidecar-injection=enabled
   kubectl label ns hipster-shop kuma.io/sidecar-injection=enabled

else
  if [  "$TYPE" = 'linkerd' ]; then
    echo " linkerd"


    echo " no ns labelling required"
  elsekubrec
     if [  "$TYPE" = 'traefik' ]; then
       echo " TraefikMesh"
     else
        if [  "$TYPE" = 'cilium' ]; then
          echo " Cilium"
        else
           if [  "$TYPE" = 'ambient' ]; then
             echo " ambient"
             kubectl label namespace otel-demo istio.io/dataplane-mode=ambient
             kubectl label namespace hipster-shop istio.io/dataplane-mode=ambient
             kubectl apply -f istio/ambientmesh/waypoint.yaml
             kubectl label namespace otel-demo istio.io/use-waypoint=otel-demo-waypoint
             kubectl label namespace hipster-shop istio.io/use-waypoint=hipstershop-waypoint
           else
              if [  "$TYPE" = 'istio' ]; then
                echo " istio"
                kubectl label namespace otel-demo istio-injection=enabled
                kubectl label namespace hipster-shop istio-injection=enabled
              else
                echo "no mesh- no annotation"
              fi
           fi
        fi
     fi
  fi
fi

if [  "$TYPE" = 'linkerd' ]; then
  linkerd inject opentelemetry/deploy_1_12.yaml  | kubectl apply -n otel-demp -f -
  linkerd inject hipstershop/k8s-manifest.yaml | kubectl apply -n hipster-shop -f -
  kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml
  kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
else
  if [  "$TYPE" = 'cilium' ]; then
    kubectl apply -f openTelemetry-manifest_ds_cilium.yaml
    kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_cilium.yaml
  else
    kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml
    kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml
  fi

  kubectl apply -f opentelemetry/deploy_1_12.yaml -n otel-demo
  kubectl apply -f hipstershop/k8s-manifest.yaml -n hipster-shop
fi


#Deploy the ingress rules
echo "--------------Demo--------------------"
echo "Installation finished "
echo "========================================================"


