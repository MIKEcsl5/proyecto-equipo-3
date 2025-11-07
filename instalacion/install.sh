#!/bin/bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
kubectl create namespace gatekeeper-system



helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set enableExternalData=true \
  --set auditInterval=60 \
  --set validatingWebhookTimeoutSeconds=5
