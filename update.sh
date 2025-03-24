#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
### type: defines which solution would be deployed in the cluster ( istio, linkerd, ambient, traefik, cilium, none)
### old : defines the previous setup used ( istio, linkerd, ambient, traefik, cilium, none)
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
       --previous)
        OLD="$2"
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

 if [ -z "$TYPE" ]; then
   echo "Error: type is  not set!"
   exit 1
 fi
 if [ -z "$OLD" ]; then
   echo "Error: type is  not set!"
   exit 1
 fi
kubectl delete -f opentelemetry/deploy_1_12.yaml -n otel-demo
kubectl delete -f hipstershop/k8s-manifest.yaml -n hipster-shop
kubectl delete -f openTelemetry-manifest_statefulset.yaml
kubectl delete -f gateway_api/gateway.yaml

# Falco
if [  "$OLD" = 'kuma' ]; then
   # get ip adress
   # removinb kuma
   echo "removing kuma"
   kubectl label ns otel-demo kuma.io/sidecar-injection-
   kubectl label ns hipster-shop kuma.io/sidecar-injection-

   kubectl delete -f kuma/MeshMetric.yaml
   kubectl delete -f kuma/MeshAccesslog.yaml
   kubectl delete -f kuma/meshtrace.yaml
   kubect delete -f  kuma/gatewayclass.yaml
   kubectl delete -f kuma/Mesh.yaml

   helm delete -n kuma-system kuma
   kubectl get crd -oname | grep --color=never 'kuma.io' | xargs kubectl delete

   GATEWAYNAME="kuma"

else
  if [  "$OLD" = 'linkerd' ]; then
     # get ip adress
     # removing linkerd
      echo "removing linkerd"
      kubectl label ns otel-demo kuma.io/sidecar-injection-
      kubectl label ns hipster-shop kuma.io/sidecar-injection-

      kubectl delete -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
      kubectl delete -f linkerd/ratelimit.yaml
      kubectl delete -f linkerd/requestTimeout.yaml
      kubectl delete -f linkerd/server_oteldemo.yaml

      # To remove Linkerd Viz
      linkerd viz uninstall | kubectl delete -f -

      # To remove Linkerd Jaeger
      linkerd jaeger uninstall | kubectl delete -f -

      # To remove Linkerd Multicluster
      linkerd uninstall | kubectl delete -f -


      kubectl get crd -oname | grep --color=never 'linkerd.io' | xargs kubectl delete
      GATEWAYNAME="linkerd"

  else
     if [  "$OLD" = 'traefik' ]; then
        # get ip adress
        # removing traefil
        echo "removing traefik"
        helm delete traefik-mesh traefik/traefik-mesh -n traefik-mesh
        GATEWAYNAME="traefik"

     else
       if [ "$OLD" = 'cilium' ]; then
         # get ip adress
         # removing cilium
          echo "removing cilium"
          helm delete cilium -n kube-system
          GATEWAYNAME="cilium"

        else
          if [ "$OLD" = 'ambient' ]; then
            # get ip adress
            #removing ambient
            echo "removing ambient"
            kubectl label ns otel-demo istio.io/dataplane-mode-
            kubectl label ns hipster-shop istio.io/dataplane-mode-
            kubectl label ns otel-demo istio.io/use-waypoint-
            kubectl label ns hipster-shop istio.io/use-waypoint-
            kubectl delete -f istio/ambientmesh/waypoint.yaml
            helm delete istio-ingress -n istio-ingress
            kubectl delete namespace istio-ingress
            helm delete ztunnel -n istio-system
            helm delete istio-cni -n istio-system
            helm delete istiod -n istio-system
            helm delete istio-base -n istio-system
            kubectl get crd -oname | grep --color=never 'istio.io' | xargs kubectl delete
            kubectl delete namespace istio-system
            GATEWAYNAME="ambient"

          else
            if [ "$OLD" = 'istio' ]; then
              #---removing istio
              echo "removing istio"
              kubectl label ns otel-demo istio-injection-
              kubectl label ns hipster-shop istio-injection-
              kubectl delete -f istio/rate_limit.yaml
              kubectl delete -f istio/request_timeout.yaml
              helm delete istio-ingress -n istio-ingress
              kubectl delete namespace istio-ingress
              helm delete istiod -n istio-system
              helm delete istio-base -n istio-system
              kubectl delete namespace istio-system
              kubectl get crd -oname | grep --color=never 'istio.io' | xargs kubectl delete
              GATEWAYNAME="istio"

            else
              echo "No needf to remover , there are  no Mesh"
              GATEWAYNAME="none"
            fi
          fi
        fi
      fi
  fi
fi
if [  "$OLD" != 'none' ]; then
  #droping gateway
  kubectl delete -f gateway_api/gateway.yaml
  sed -i  '' "s,$GATEWAYNAME,CLASSNAME_REPLACE,"  gateway_api/gateway.yaml

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
       helm install traefik-mesh traefik/traefik-mesh --set kubedns=true --set controller.image.pullPolicy=IfNotPresent --set controller.image.tag=latest
       kubectl label namespace otel-demo kuma.io/sidecar-injection=enabled
       kubectl label ns hipster-shop kuma.io/sidecar-injection=enabled
       GATEWAYNAME="traefik"

     else
        if [  "$TYPE" = 'cilium' ]; then
          echo "installing Cilium"
          helm upgrade cilium cilium/cilium --version 1.17.1 \
              --namespace kube-system \
              --reuse-values \
              --set kubeProxyReplacement=true \
              --set envoyConfig.enabled=true \
              --set gatewayAPI.enabled=true
          GATEWAYNAME="cilium"
        else
           if [  "$TYPE" = 'ambient' ]; then
             echo "installing ambient"
             helm repo add istio https://istio-release.storage.googleapis.com/charts
             helm repo update istio
             helm install istio-base istio/base -n istio-system --create-namespace --wait
             helm install istiod istio/istiod --namespace istio-system --set profile=ambient -f istio/values.yaml --wait
             helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
             helm install ztunnel istio/ztunnel -n istio-system --wait
             helm install istio-ingress istio/gateway -n istio-ingress --create-namespace --wait

             kubectl label namespace otel-demo istio.io/dataplane-mode=ambient
             kubectl label namespace hipster-shop istio.io/dataplane-mode=ambient
             kubectl apply -f istio/ambientmesh/waypoint.yaml
             kubectl label namespace otel-demo istio.io/use-waypoint=otel-demo-waypoint
             kubectl label namespace hipster-shop istio.io/use-waypoint=hipstershop-waypoint

             GATEWAYNAME=kuma

           else
            if [  "$TYPE" = 'istio' ]; then
              echo "installing istio"
              helm repo add istio https://istio-release.storage.googleapis.com/charts
              helm repo update
              helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
              helm install istiod istio/istiod -n istio-system  -f istio/values.yaml --wait
              GATEWAYNAME="istio"
              kubectl label namespace otel-demo istio-injection=enabled
              kubectl label namespace hipster-shop istio-injection=enabled

            else
              #no mesh
              echo "no Mesh deployed"
              GATEWAYNAME="none"

            fi

           fi
        fi
     fi
  fi
fi
if [  "$TYPE" != 'none' ]; then
  #creatin gateway
  sed -i  '' "s,CLASSNAME_REPLACE,$GATEWAYNAME,"  gateway_api/gateway.yaml
fi

if [  "$TYPE" = 'linkerd' ]; then
  linkerd inject opentelemetry/deploy_1_12.yaml  | kubectl apply -n otel-demp -f -
  linkerd inject hipstershop/k8s-manifest.yaml | kubectl apply -n hipster-shop -f -
  kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
else
  kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml
  kubectl apply -f opentelemetry/deploy_1_12.yaml -n otel-demo
  kubectl apply -f hipstershop/k8s-manifest.yaml -n hipster-shop
fi