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
kubectl delete -f opentelemetry/policy.yaml
kubectl delete -f opentelemetry/simpleroute.yaml

kubectl delete -f opentelemetry/deploy_1_12.yaml -n otel-demo



# Falco
if [  "$OLD" = 'kuma' ]; then
   # get ip adress
   # removinb kuma
   echo "removing kuma"
   kubectl label ns otel-demo kuma.io/sidecar-injection-
   kubectl delete -f opentelemetry/openTelemetry-manifest_statefulset.yaml
   kubectl delete -f kuma/MeshMetric.yaml
   kubectl delete -f kuma/MeshAccesslog.yaml
   kubectl delete -f kuma/meshtrace.yaml
   kubectl delete -f  kuma/gatewayclass.yaml
   kubectl delete -f kuma/Mesh.yaml
   kubectl delete -f kuma/kuma_gateway.yaml
   kubectl delete -f kuma/referencegrant.yaml
   helm delete -n kuma-system kuma
   kubectl get crd -oname | grep --color=never 'kuma.io' | xargs kubectl delete

else
  if [  "$OLD" = 'linkerd' ]; then
     # get ip adress
     # removing linkerd
      echo "removing linkerd"
      kubectl annotate ns otel-demo linkerd.io/inject-
      kubectl delete -f linkerd/gateway.yaml
      kubectl delete -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
      kubectl delete -f linkerd/referencegrant.yaml
      helm uninstall kgateway -n kgateway-system
      helm uninstall kgateway-crds -n kgateway-system
      helm uninstall linkerd-jaeger -n  linkerd
      helm uninstall linkerd-control-plane -n linkerd
      helm uninstall linkerd-crds -n linkerd

      kubectl get crd -oname | grep --color=never 'linkerd.io' | xargs kubectl delete


  else

     if [ "$OLD" = 'ambient-kgateway' ]; then
       # get ip adress
       # removing cilium
        echo "removing kgateway and ambiernt"
        kubectl delete -f opentelemetry/openTelemetry-manifest_statefulset_kgateway.yaml
        kubectl delete -f kgateway-ambient/gateway.yaml
        kubdectl delete -f kgateway-ambient/waypoint.yaml
        kubectl delete -f kgateway-ambient/observability.yaml
        kubectl label ns otel-demo istio.io/dataplane-mode-
        kubectl label ns otel-demo istio.io/use-waypoint-
        kubectl delete -f kgateway-ambient/referencegrant.yaml
        helm delete istio-ingress -n istio-ingress
        kubectl delete namespace istio-ingress
        helm uninstall kgateway -n kgateway-system
        helm uninstall kgateway-crds -n kgateway-system
        helm delete ztunnel -n istio-system
        helm delete istio-cni -n istio-system
        helm delete istiod -n istio-system
        helm delete istio-base -n istio-system
        kubectl get crd -oname | grep --color=never 'istio.io' | xargs kubectl delete
        kubectl delete namespace istio-system
      else
        if [ "$OLD" = 'ambient' ]; then
          # get ip adress
          #removing ambient
          echo "removing ambient"
          kubectl delete -f istio/gateway.yaml
          kubectl delete -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
          kubectl label ns otel-demo istio.io/dataplane-mode-
          kubectl label ns otel-demo istio.io/use-waypoint-
          kubectl delete -f istio/ambientmesh/waypoint.yaml
          kubectl delete -f istio/referencegrant.yaml
          helm delete istio-ingress -n istio-ingress
          kubectl delete namespace istio-ingress

          helm delete ztunnel -n istio-system
          helm delete istio-cni -n istio-system
          helm delete istiod -n istio-system
          helm delete istio-base -n istio-system
          kubectl get crd -oname | grep --color=never 'istio.io' | xargs kubectl delete
          kubectl delete namespace istio-system


        else
          if [ "$OLD" = 'istio' ]; then
            #---removing istio
            echo "removing istio"
            kubectl delete -f istio/gateway.yaml
            kubectl label ns otel-demo istio-injection-
            kubectl delete -f istio/rate_limit.yaml
            kubectl delete -f istio/request_timeout.yaml
            kubectl delete -f istio/referencegrant.yaml
            helm delete istio-ingress -n istio-ingress
            kubectl delete namespace istio-ingress
            helm delete istiod -n istio-system
            helm delete istio-base -n istio-system
            kubectl delete namespace istio-system
            kubectl get crd -oname | grep --color=never 'istio.io' | xargs kubectl delete


          else
            echo "No needf to remover , there are  no Mesh"
          fi
        fi
      fi

  fi
fi

#-----Installing mesh-----------------
if [  "$TYPE" = 'kuma' ]; then
  echo "installing kuma"
  helm repo add kuma https://kumahq.github.io/charts
  helm repo update
  helm install --create-namespace --namespace kuma-system kuma kuma/kuma
  kubectl apply -f kuma/gatewayclass.yaml
  kubectl apply -f kuma/MeshMetric.yaml
  kubectl apply -f kuma/MeshMetric.yaml
  kubectl apply -f kuma/meshtrace.yaml
  kubectl apply -f kuma/MeshAccesslog.yaml
  kubectl label namespace otel-demo kuma.io/sidecar-injection=enabled
  kubectl apply -f kuma/kuma_gateway.yaml
  kubectl apply -f opentelemetry/simpleroute.yaml
  kubectl apply -f openTelemetry-manifest_statefulset.yaml
  kubectl apply -f kuma/referencegrant.yaml
else
  if [  "$TYPE" = 'linkerd' ]; then

    echo "installing linkerd"
    step certificate create root.linkerd.cluster.local ca.crt ca.key \
    --profile root-ca --no-password --insecure
    step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
    --profile intermediate-ca --not-after 8760h --no-password --insecure \
    --ca ca.crt --ca-key ca.key
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
     helm install --create-namespace --namespace kgateway-system --version v2.1.0-main \
     kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
     --set controller.image.pullPolicy=Always

     helm install --namespace kgateway-system --version v2.1.0-main \
          kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
          --set controller.image.pullPolicy=Always --set agentgateway.enabled=true --set waypoint.enabled=false
    kubectl apply -f linkerd/gateway.yaml
    kubectl annotate ns otel-demo linkerd.io/inject=enabled
    kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_linkerd.yaml
    kubectl apply -f linkerd/referencegrant.yaml
  else

    if [  "$TYPE" = 'ambient-kgateway' ]; then
      echo "installing ambient"
       helm repo add istio https://istio-release.storage.googleapis.com/charts
       helm repo update istio
       helm install istio-base istio/base -n istio-system --create-namespace --wait
       helm install istiod istio/istiod --namespace istio-system --set profile=ambient -f istio/ambientmesh/values.yaml --wait
       helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
       helm install ztunnel istio/ztunnel -n istio-system  --wait

       echo "installing kgatewa"
       # Install kgateway
       helm install --create-namespace --namespace kgateway-system --version v2.1.0-main \
       kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
       --set controller.image.pullPolicy=Always

       helm install --namespace kgateway-system --version v2.1.0-main \
       kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
       --set controller.image.pullPolicy=Always --set agentgateway.enabled=true --set waypoint.enabled=true

        kubectl apply -f kgateway-ambient/gateway.yaml
        kubectl label namespace otel-demo istio.io/dataplane-mode=ambient
        kubectl apply -f kgateway-ambient/waypoint.yaml
        kubectl label namespace otel-demo istio.io/use-waypoint=kgateway-waypoint
        kubectl apply -f kgateway-ambient/observability.yaml
        kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_kgateway.yaml
        kubectl apply -f kgateway-ambient/referencegrant.yaml
    else
       if [  "$TYPE" = 'ambient' ]; then
         echo "installing ambient"

         helm repo add istio https://istio-release.storage.googleapis.com/charts
         helm repo update istio
         helm install istio-base istio/base -n istio-system --create-namespace --wait
         helm install istiod istio/istiod --namespace istio-system --set profile=ambient -f istio/ambientmesh/values.yaml --wait
         helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait
         helm install ztunnel istio/ztunnel -n istio-system  --wait

         kubectl apply -f istio/gateway.yaml
         kubectl label namespace otel-demo istio.io/dataplane-mode=ambient
         kubectl apply -f istio/ambientmesh/waypoint.yaml
         kubectl label namespace otel-demo istio.io/use-waypoint=otel-demo-waypoint
         kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
         kubectl apply -f istio/referencegrant.yaml


       else
        if [  "$TYPE" = 'istio' ]; then
          echo "installing istio"
          helm repo add istio https://istio-release.storage.googleapis.com/charts
          helm repo update
          helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
          helm install istiod istio/istiod -n istio-system  -f istio/values.yaml --wait
          kubectl apply -f istio/gateway.yaml
          kubectl label namespace otel-demo istio-injection=enabled
          kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset_istio.yaml
          kubectl apply -f istio/referencegrant.yaml

        else
          #no mesh
          echo "no Mesh deployed"
          kubectl apply -f openTelemetry-manifest_statefulset.yaml

        fi

       fi
    fi

  fi
fi

kubectl apply -f opentelemetry/deploy_1_12.yaml -n otel-demo
if [  "$TYPE" != 'none' ]; then
  if [  "$TYPE" != 'ambient-kgateway' ]; then
    kubectl apply -f kgateway-ambient/simpleroute.yaml
    #kubectl apply -f opentelemetry/policy.yaml
  else
    kubectl apply -f opentelemetry/simpleroute.yaml
  fi
fi