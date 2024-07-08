#!/bin/bash
export KARPENTER_VERSION=0.37 #Replace with the Karpenter version number you intend to deploy
export CLUSTER_NAME=aloda-test #replace your  eks cluster name

TEMPOUT=$(mktemp)

curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/main/website/content/en/v${KARPENTER_VERSION}/getting-started/getting-started-with-karpenter/cloudformation.yaml > $TEMPOUT \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

eksctl create iamidentitymapping \
  --username system:node:{{EC2PrivateDNSName}} \
  --cluster  ${CLUSTER_NAME} \
  --arn "arn:aws:iam::${ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --group system:bootstrappers \
  --group system:nodes