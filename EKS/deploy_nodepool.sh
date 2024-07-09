#!/bin/bash

export K8S_VERSION="1.29"
export CLUSTER_NAME="aloda-test-karpenter"
export ARM_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-arm64/recommended/image_id --query Parameter.Value --output text)"
export AMD_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2/recommended/image_id --query Parameter.Value --output text)"
export GPU_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-gpu/recommended/image_id --query Parameter.Value --output text)"
#替换成您的密钥对名称
export AUTHORIZED_KEYS=$(cat eks/authorized_keys)
#替换成您的安全组ID
export SECURITY_GROUP_ID="sg-0741db1664c1fc102"
cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        intent: apps
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large", "c5.large"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 10
    memory: 32Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h # 30 * 24h = 720h
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2 # Amazon Linux 2
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  tags:
    KarpenterManaged: "true"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
  amiSelectorTerms:
    - id: "${AMD_AMI_ID}"
    - id: "${ARM_AMI_ID}"
  securityGroupSelectorTerms:
    # Select on any security group that has both the "karpenter.sh/discovery: ${CLUSTER_NAME}" tag
    # AND the "environment: test" tag OR any security group with the "my-security-group" name
    # OR any security group with ID "sg-063d7acfb4b06c82c"
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
    #- name: my-security-group
    - id: ${SECURITY_GROUP_ID}
  userData: |
      #!/bin/bash
      mkdir -p ~ec2-user/.ssh/
      touch ~ec2-user/.ssh/authorized_keys
      echo "$AUTHORIZED_KEYS" >>~ec2-user/.ssh/authorized_keys
      chmod -R go-w ~ec2-user/.ssh/authorized_keys
      chown -R ec2-user ~ec2-user/.ssh
EOF

#利用用户数据推送密钥对到karpenter的ec2 node class启动是实例中