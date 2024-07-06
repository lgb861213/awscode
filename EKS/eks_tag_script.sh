#!/bin/bash

###############################################################################
#FileName: eks_tag_script.sh
#Author: Aloda
#Date:   2024-07-05
#LastModifyDate: 2024-07-05
#Description: This script is used in the EKS cluster to automatically
# add the tags required by ELB and karpenter，
# and can also support delete the specified tags.
###############################################################################

#########################variables############################
VPC_ID=""
SUBNET_IDS=""
PUBLIC_SUBNET_IDS=""
PRIVATE_SUBNET_IDS=""

get_eks_subnets(){
   read -p "Enter eks cluster name:" CLUSTER_NAME
   read -p "Enter region (press Enter for default us-east-1): " REGION
   #若区域未提供将默认使用us-east-1
   if [ -z "$REGION" ]; then
     REGION="us-east-1"
   fi

  #获取 VPC ID 并存储在全局变量中
  echo "正在获取eks集群的vpc信息..."
  VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)
  # 检查命令是否成功执行
  if [ $? -ne 0 ]; then
      echo "错误: 无法找到名为 '$CLUSTER_NAME' 的 EKS 集群。"
      echo "请输入正确的集群名称..."
      exit 1
  fi
  echo "正在获取vpc关联使用的igw..."
  IGW_ID=$(aws ec2 describe-internet-gateways --region $REGION --filters Name=attachment.vpc-id,Values=${VPC_ID} --query "InternetGateways[].InternetGatewayId"  | jq -r '.[0]')

  echo "正在获取公有子网信息..."
  PUBLIC_SUBNETS=`aws ec2 describe-route-tables --region $REGION\
    --query  'RouteTables[*].Associations[].SubnetId' \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
      "Name=route.gateway-id,Values=${IGW_ID}" \
    | jq . -c`

  echo "正在获取私有子网信息..."
  PRIVATE_SUBNETS=$(aws ec2 describe-subnets --region $REGION \
    --filter Name=vpc-id,Values=${VPC_ID} \
    --query 'Subnets[].SubnetId' \
    | jq -c '[ .[] | select( . as $i | '${PUBLIC_SUBNETS}' | index($i) | not) ]')

  # 删除字符串中的引号和方括号，并使用逗号分隔子网 ID
  PUBLIC_SUBNET_IDS=$(echo $PUBLIC_SUBNETS | sed 's/[][]//g' | sed 's/"//g' | sed 's/,/ /g')
  PRIVATE_SUBNET_IDS=$(echo $PRIVATE_SUBNETS | sed 's/[][]//g' | sed 's/"//g' | sed 's/,/ /g')
}

get_vpc_subnets(){
   read -p "Enter vpc id:" VPC_ID
   read -p "Enter region (press Enter for default us-east-1): " REGION
   #若区域未提供将默认使用us-east-1
   if [ -z "$REGION" ]; then
       REGION="us-east-1"
   fi
  #获取vpc下的所有子网信息
  echo "正在获取${VPC_ID}的所有子网id信息..."
  SUBNETS=$(aws ec2 describe-subnets --region $REGION  --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[].SubnetId" --output text)
  # 删除字符串中的引号和方括号，并使用逗号分隔子网 ID
  SUBNET_IDS=$(echo $SUBNETS | sed 's/[][]//g' | sed 's/"//g' | sed 's/,/ /g')
}
# 函数：add_ec2_resource_tag
# 描述：为指定的AWS EC2资源（如子网、安全组等）添加标签
# 用途：在AWS环境中管理和组织EC2资源，便于分类、筛选和自动化操作
#
# 参数：
#   $1 - RESOURCE_ID: 要添加标签的EC2资源ID（字符串，如子网ID或安全组ID）
#   $2 - TAG_KEY: 标签的键（字符串）
#   $3 - TAG_VALUE: 标签的值（字符串）
#
# 返回：无
#
# 使用示例：
#   add_ec2_resource_tag "subnet-1234567890abcdef0" "Environment" "Production"
#   add_ec2_resource_tag "sg-0987654321fedcba0" "Project" "WebApp"
#
# 注意：
# - 确保已正确配置AWS CLI，并具有适当的权限来修改EC2资源
# - 此函数不会检查资源ID的有效性，请确保提供正确的资源ID
function add_ec2_resource_tag() {
  local RESOURCE_ID="$1"
  local TAG_KEY="$2"
  local TAG_VALUE="$3"
  echo "正在为${RESOURCE_ID}的资源打以${TAG_KEY}为tag key,以${TAG_VALUE}作为值的标签信息"
  aws ec2 create-tags --resources $RESOURCE_ID --tags Key=$TAG_KEY,Value=$TAG_VALUE
  echo "已为资源 $RESOURCE_ID 添加标签 $TAG_KEY=$TAG_VALUE"
}

# 函数：remove_ec2_resource_tag
# 描述：从指定的AWS EC2资源（如子网、安全组等）中删除标签
# 用途：在AWS环境中管理EC2资源的标签，用于清理或更新标签信息
#
# 参数：
#   $1 - RESOURCE_ID: 要删除标签的EC2资源ID（字符串，如子网ID或安全组ID）
#   $2 - TAG_KEY: 要删除的标签的键（字符串）
#   $3 - TAG_VALUE: 要删除的标签的值（字符串，可选）
#
# 返回：无
#
# 使用示例：
#   remove_ec2_resource_tag "subnet-1234567890abcdef0" "Environment" "Production"
#   remove_ec2_resource_tag "sg-0987654321fedcba0" "Project"
#
# 注意：
# - 确保已正确配置AWS CLI，并具有适当的权限来修改EC2资源的标签
# - 此函数不会检查资源ID的有效性，请确保提供正确的资源ID
# - 如果不指定TAG_VALUE，函数将删除指定TAG_KEY的所有标签，无论其值如何
# - 如果指定的标签不存在，AWS CLI 通常不会报错，但也不会进行任何更改
function remove_ec2_resource_tag() {
  local RESOURCE_ID="$1"
  local TAG_KEY="$2"
  local TAG_VALUE="$3"

  if [ -z "$TAG_VALUE" ]; then
    # 如果没有提供TAG_VALUE，则删除指定KEY的所有标签
    aws ec2 delete-tags --resources "$RESOURCE_ID" --tags Key="$TAG_KEY"
    echo "已从资源 $RESOURCE_ID 中删除标签(key)为 ${TAG_KEY} 的标签"
  else
    # 如果提供了TAG_VALUE，则删除指定的KEY-VALUE对
    aws ec2 delete-tags --resources "$RESOURCE_ID" --tags Key="$TAG_KEY",Value="$TAG_VALUE"
    echo "已从资源 $RESOURCE_ID 中删除标签(key)为${TAG_KEY}，标签（value)为${TAG_VALUE}的标签"
  fi
}



function main(){
  # 安装 jq 命令判断
  if ! command -v jq &> /dev/null; then
      echo "脚本需要 jq 命令，请先安装 jq 后再运行脚本。"
      echo "您可以使用以下命令在 Ubuntu 上安装 jq："
      echo "sudo apt-get update && sudo apt-get install -y jq"
      exit 1
  fi
  echo -e "\033[1;31m
###################################################################################################
#               Menu
#  1: Add tag key for special vpc all subnets
#  2: Remove tag key for special vpc all subnets
#  3: Add or Remove tag key for special subnets
#  4. Add the tag keys and values required by elb to the eks cluster
#  5. Remove the tag keys  required by elb to the eks cluster
#  6. Add the tag key and value required by karpenter to the specified node group of the eks cluster
#  7. Add tag key for special vpc subnet
#  8. Remove tag key for special vpc subnet
#  9. Exit
##################################################################################################### \033[0m"
  read -p "Please choice[1-9]:"
      case $REPLY in
      1)
        get_vpc_subnets
        read -p "Enter the tag key:" TAG_KEY
        read -p "Enter the tag value:" TAG_VALUE
        for subnet in ${SUBNET_IDS};do
          echo "正在为${subnet}资源添加标签，该标签的(key)为${TAG_KEY},值为${TAG_VALUE} ..."
          add_ec2_resource_tag "${subnet}" "${TAG_KEY}" "${TAG_VALUE}"
        done
      ;;
      2)
        get_vpc_subnets
        read -p "Enter the tag key:" TAG_KEY
        read -p "Enter the tag value:" TAG_VALUE
        for subnet in ${SUBNET_IDS};do
            echo "正在为${subnet}资源移除标签，该标签的(key)为${TAG_KEY},值为${TAG_VALUE} ..."
            remove_ec2_resource_tag "${subnet}" "${TAG_KEY}" "${TAG_VALUE}"
        done
      ;;
      3)
       #要求输入子网id信息
       read -p "Enter subnet ID(s) (use spaces to separate multiple IDs): " SUBNETS
       read -p "Enter the tag key:" TAG_KEY
       read -p "Enter the tag value:" TAG_VALUE
       read -p "Enter operation (a for add, r for remove tags): " OPS
       for subnet in ${SUBNETS};do
         if [ "$OPS" = "a" ];then
           echo "正在为${subnet}资源添加标签，该标签的(key)为${TAG_KEY},值为${TAG_VALUE} ..."
           add_ec2_resource_tag "${subnet}" "${TAG_KEY}" "${TAG_VALUE}"
         elif [ "$OPS" = "r" ];then
           echo "正在为${subnet}资源移除标签，该标签的(key)为${TAG_KEY},值为${TAG_VALUE} ..."
           remove_ec2_resource_tag "${subnet}" "${TAG_KEY}" "${TAG_VALUE}"
         else
            echo "Invalid operation. Please enter 'a' or 'r'."
            exit 1
         fi
       done
      ;;
      4)
        get_eks_subnets
        #####eks集群结合loadbalancer controller所需子网的tag信息###############
        PUBLIC_SUBNETS_TAG_KEY="kubernetes.io/role/elb"
        TAG_VALUE="1"
        PRIVATE_SUBNETS_TAG_KEY="kubernetes.io/role/internal-elb"
        for SUBNET_ID in $PUBLIC_SUBNET_IDS; do
              echo "正在为${SUBNET_ID}公有子网打上tag标签信息..."
              add_ec2_resource_tag "${SUBNET_ID}" "${PUBLIC_SUBNETS_TAG_KEY}" "${TAG_VALUE}"
        done
        for SUBNET_ID in $PRIVATE_SUBNET_IDS; do
              echo "正在为${SUBNET_ID}私有子网打上tag标签信息..."
              add_ec2_resource_tag $SUBNET_ID $PRIVATE_SUBNETS_TAG_KEY $TAG_VALUE
        done
        ;;
      5)
        get_eks_subnets
        #####eks集群结合loadbalancer controller所需子网的tag信息###############
        PUBLIC_SUBNETS_TAG_KEY="kubernetes.io/role/elb"
        TAG_VALUE="1"
        PRIVATE_SUBNETS_TAG_KEY="kubernetes.io/role/internal-elb"
        for SUBNET_ID in $PUBLIC_SUBNET_IDS; do
            echo "正在为${SUBNET_ID}公有子网移除${PUBLIC_SUBNETS_TAG_KEY}的tag标签信息..."
                      remove_ec2_resource_tag "${SUBNET_ID}" "${PUBLIC_SUBNETS_TAG_KEY}" "${TAG_VALUE}"
        done
        for SUBNET_ID in $PRIVATE_SUBNET_IDS; do
            echo "正在为${SUBNET_ID}私有子网移除${PRIVATE_SUBNETS_TAG_KEY}的tag标签信息..."
            remove_ec2_resource_tag $SUBNET_ID $PRIVATE_SUBNETS_TAG_KEY $TAG_VALUE
        done
        ;;
      6)
        ;;
      7)
        ;;
      8)
        ;;
      9)
        exit 0
        ;;
      *)
        echo -e "\033[31;5m	invalid input	    \033[0m"
         main
      ;;
      esac

}

#############
main

#####
