#! /bin/bash

export CLUSTER_NAME="aloda-test-karpenter" #replace your eks cluster name
export KARPENTER_VERSION="0.36.2" # Replace with the Karpenter version number you intend to deploy
export KARPENTER_NAMESPACE="karpenter" # Replace with the karpenter namespace name you intend to deploy
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export KARPENTER_IAM_ROLE_NAME="karpenterControllerRole-${CLUSTER_NAME}"
export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/karpenterControllerRole-${CLUSTER_NAME}"
export KARPENTER_IAM_NodeROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
export KARPENTER_NODE_INSTANCE_PROFILE_NAME="KarpenterNodeInstanceProfile-${CLUSTER_NAME}"

#检查karpenter Controller 角色是否存在
if aws iam get-role --role-name "${KARPENTER_IAM_ROLE_NAME}" >/dev/null 2>&1; then
    echo "Karpenter Controller 角色 ${KARPENTER_IAM_ROLE_NAME} 已存在,将继续执行部署安装"
else
    echo "错误: Karpenter Controller 角色 ${KARPENTER_IAM_ROLE_NAME} 不存在"
    exit 1
fi

#检查karpenter Node 角色是否存在
if aws iam get-role --role-name "${KARPENTER_IAM_NodeROLE_NAME}" >/dev/null 2>&1; then
    echo "Karpenter Node 角色 ${KARPENTER_IAM_NodeROLE_NAME} 已存在,将继续执行部署安装"
else
    echo "错误: Karpenter Node 角色 ${KARPENTER_IAM_NodeROLE_NAME} 不存在"
    exit 1
fi

#检查 Node Instance Profile 是否存在
if aws iam get-instance-profile --instance-profile-name "${KARPENTER_NODE_INSTANCE_PROFILE_NAME}" >/dev/null 2>&1; then
    echo "Node Instance Profile ${KARPENTER_NODE_INSTANCE_PROFILE_NAME} 已存在"
else
    echo "错误: Node Instance Profile ${KARPENTER_NODE_INSTANCE_PROFILE_NAME} 不存在"
    exit 1
fi


# 如果所有检查都通过，继续安装
echo "所有必需的角色和实例配置文件都存在，可以继续安装 Karpenter"

#  --set "settings.defaultInstanceProfile=${KARPENTER_NODE_INSTANCE_PROFILE_NAME}" \
#helm registry logout public.ecr.aws
export http_proxy=http://127.0.0.1:1081 #若有使用proxy则可以做启用，需要将1081替换成proxy使用的端口号
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set serviceAccount.create=true \
  --set serviceAccount.name=karpenter \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueueName=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait