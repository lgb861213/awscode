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

#create instace profile
echo "正在创建 KarpenterNodeInstanceProfile-${CLUSTER_NAME} instance profile..."
aws iam create-instance-profile \
    --instance-profile-name "KarpenterNodeInstanceProfile-${CLUSTER_NAME}"
# attache the  IAM role to an ec2 intance profile
echo "正在将 KarpenterNodeInstanceProfile-${CLUSTER_NAME} instance profile 关联到 KarpenterNodeRole-${CLUSTER_NAME} 角色..."
aws iam add-role-to-instance-profile \
--instance-profile-name "KarpenterNodeInstanceProfile-${CLUSTER_NAME}" \
--role-name "KarpenterNodeRole-${CLUSTER_NAME}"