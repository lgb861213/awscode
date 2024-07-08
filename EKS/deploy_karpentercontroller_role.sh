#!/bin/bash
export CLUSTER_NAME=aloda-test #replace your eks cluster name
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve
sleep 1
#创建IAM角色并且不创建SA账号
eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name karpenter --namespace karpenter \
  --role-name "karpenterControllerRole-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
  --role-only \
  --approve

#export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/karpenterControllerRole-${CLUSTER_NAME}"
