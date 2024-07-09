#!/bin/bash
export CLUSTER_NAME=aloda-test-karpenter #replace your eks cluster name
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

#create the  ec2 spot linked role
echo "正在创建 AWSServiceRoleForEC2Spot 角色"
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com 2> /dev/null || echo 'Already exist'
