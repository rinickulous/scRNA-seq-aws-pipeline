#!/bin/bash

# AWS Batch Setup Script for scRNA-seq Pipeline
# This script sets up the necessary AWS Batch infrastructure

set -e

# Configuration variables
REGION=${AWS_REGION:-"us-east-1"}
COMPUTE_ENV_NAME="scrna-seq-compute-env"
JOB_QUEUE_NAME="scrna-seq-job-queue"
VPC_ID=""
SUBNET_ID=""
SECURITY_GROUP_ID=""
INSTANCE_ROLE_NAME="ecsInstanceRole"
SERVICE_ROLE_NAME="AWSBatchServiceRole"
SPOT_ROLE_NAME="AmazonEC2SpotFleetRole"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up AWS Batch infrastructure for scRNA-seq pipeline${NC}"

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}AWS CLI found${NC}"
}

# Function to get default VPC and subnet
get_network_info() {
    echo -e "${YELLOW}Getting default VPC and subnet information...${NC}"
    
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --region $REGION \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text)
    
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        echo -e "${RED}No default VPC found. Please create one or specify a VPC ID.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Found VPC: $VPC_ID${NC}"
    
    # Get subnets in the VPC
    SUBNET_ID=$(aws ec2 describe-subnets \
        --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[0].SubnetId" \
        --output text)
    
    echo -e "${GREEN}Found Subnet: $SUBNET_ID${NC}"
    
    # Get or create security group
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=scrna-seq-batch-sg" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null || echo "None")
    
    if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
        echo -e "${YELLOW}Creating security group...${NC}"
        SECURITY_GROUP_ID=$(aws ec2 create-security-group \
            --region $REGION \
            --group-name scrna-seq-batch-sg \
            --description "Security group for scRNA-seq Batch compute environment" \
            --vpc-id $VPC_ID \
            --output text)
        
        # Add outbound rule for internet access
        aws ec2 authorize-security-group-egress \
            --region $REGION \
            --group-id $SECURITY_GROUP_ID \
            --protocol all \
            --cidr 0.0.0.0/0 2>/dev/null || true
    fi
    
    echo -e "${GREEN}Security Group: $SECURITY_GROUP_ID${NC}"
}

# Function to create IAM roles
create_iam_roles() {
    echo -e "${YELLOW}Setting up IAM roles...${NC}"
    
    # Create ECS Instance Role if it doesn't exist
    if ! aws iam get-role --role-name $INSTANCE_ROLE_NAME &>/dev/null; then
        echo -e "${YELLOW}Creating ECS Instance Role...${NC}"
        
        cat > /tmp/ecs-instance-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        aws iam create-role \
            --role-name $INSTANCE_ROLE_NAME \
            --assume-role-policy-document file:///tmp/ecs-instance-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name $INSTANCE_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
        
        aws iam attach-role-policy \
            --role-name $INSTANCE_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        # Create instance profile
        aws iam create-instance-profile --instance-profile-name $INSTANCE_ROLE_NAME 2>/dev/null || true
        aws iam add-role-to-instance-profile \
            --instance-profile-name $INSTANCE_ROLE_NAME \
            --role-name $INSTANCE_ROLE_NAME 2>/dev/null || true
    fi
    
    # Create Batch Service Role if it doesn't exist
    if ! aws iam get-role --role-name $SERVICE_ROLE_NAME &>/dev/null; then
        echo -e "${YELLOW}Creating Batch Service Role...${NC}"
        
        cat > /tmp/batch-service-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "batch.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        aws iam create-role \
            --role-name $SERVICE_ROLE_NAME \
            --assume-role-policy-document file:///tmp/batch-service-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name $SERVICE_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole
    fi
    
    # Create Spot Fleet Role if it doesn't exist
    if ! aws iam get-role --role-name $SPOT_ROLE_NAME &>/dev/null; then
        echo -e "${YELLOW}Creating Spot Fleet Role...${NC}"
        
        cat > /tmp/spot-fleet-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "spotfleet.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        aws iam create-role \
            --role-name $SPOT_ROLE_NAME \
            --assume-role-policy-document file:///tmp/spot-fleet-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name $SPOT_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRole
    fi
    
    echo -e "${GREEN}IAM roles setup complete${NC}"
}

# Function to create compute environment
create_compute_environment() {
    echo -e "${YELLOW}Creating Batch compute environment...${NC}"
    
    # Check if compute environment already exists
    if aws batch describe-compute-environments \
        --region $REGION \
        --compute-environments $COMPUTE_ENV_NAME \
        --query "computeEnvironments[0].computeEnvironmentName" \
        --output text 2>/dev/null | grep -q $COMPUTE_ENV_NAME; then
        echo -e "${YELLOW}Compute environment already exists. Updating...${NC}"
        
        # Disable the compute environment first
        aws batch update-compute-environment \
            --region $REGION \
            --compute-environment $COMPUTE_ENV_NAME \
            --state DISABLED
        
        # Wait for it to be disabled
        sleep 10
        
        # Delete it
        aws batch delete-compute-environment \
            --region $REGION \
            --compute-environment $COMPUTE_ENV_NAME
        
        # Wait for deletion
        sleep 20
    fi
    
    # Get role ARNs
    SERVICE_ROLE_ARN=$(aws iam get-role --role-name $SERVICE_ROLE_NAME --query 'Role.Arn' --output text)
    INSTANCE_ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):instance-profile/$INSTANCE_ROLE_NAME"
    SPOT_ROLE_ARN=$(aws iam get-role --role-name $SPOT_ROLE_NAME --query 'Role.Arn' --output text)
    
    # Create compute environment
    aws batch create-compute-environment \
        --region $REGION \
        --compute-environment-name $COMPUTE_ENV_NAME \
        --type MANAGED \
        --state ENABLED \
        --service-role $SERVICE_ROLE_ARN \
        --compute-resources type=EC2_SPOT,minvCpus=0,maxvCpus=256,desiredvCpus=4,instanceTypes=optimal,subnets=$SUBNET_ID,securityGroupIds=$SECURITY_GROUP_ID,instanceRole=$INSTANCE_ROLE_ARN,bidPercentage=100,spotIamFleetRole=$SPOT_ROLE_ARN
    
    echo -e "${GREEN}Compute environment created: $COMPUTE_ENV_NAME${NC}"
}

# Function to create job queue
create_job_queue() {
    echo -e "${YELLOW}Creating Batch job queue...${NC}"
    
    # Check if job queue already exists
    if aws batch describe-job-queues \
        --region $REGION \
        --job-queues $JOB_QUEUE_NAME \
        --query "jobQueues[0].jobQueueName" \
        --output text 2>/dev/null | grep -q $JOB_QUEUE_NAME; then
        echo -e "${YELLOW}Job queue already exists. Updating...${NC}"
        
        # Disable and delete the job queue
        aws batch update-job-queue \
            --region $REGION \
            --job-queue $JOB_QUEUE_NAME \
            --state DISABLED
        
        sleep 10
        
        aws batch delete-job-queue \
            --region $REGION \
            --job-queue $JOB_QUEUE_NAME
        
        sleep 10
    fi
    
    # Wait for compute environment to be ready
    echo -e "${YELLOW}Waiting for compute environment to be ready...${NC}"
    while true; do
        STATUS=$(aws batch describe-compute-environments \
            --region $REGION \
            --compute-environments $COMPUTE_ENV_NAME \
            --query "computeEnvironments[0].status" \
            --output text)
        
        if [ "$STATUS" == "VALID" ]; then
            break
        fi
        
        echo -e "${YELLOW}Compute environment status: $STATUS. Waiting...${NC}"
        sleep 5
    done
    
    # Create job queue
    aws batch create-job-queue \
        --region $REGION \
        --job-queue-name $JOB_QUEUE_NAME \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order order=1,computeEnvironment=$COMPUTE_ENV_NAME
    
    echo -e "${GREEN}Job queue created: $JOB_QUEUE_NAME${NC}"
}

# Main execution
main() {
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}AWS Batch Setup for scRNA-seq Pipeline${NC}"
    echo -e "${GREEN}===============================================${NC}"
    
    check_aws_cli
    get_network_info
    create_iam_roles
    create_compute_environment
    create_job_queue
    
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}Setup complete!${NC}"
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${YELLOW}Use the following in your Nextflow configuration:${NC}"
    echo -e "  AWS Region: ${GREEN}$REGION${NC}"
    echo -e "  Job Queue: ${GREEN}$JOB_QUEUE_NAME${NC}"
    echo -e ""
    echo -e "${YELLOW}Run your pipeline with:${NC}"
    echo -e "${GREEN}nextflow run main.nf -profile awsbatch --awsqueue $JOB_QUEUE_NAME --awsregion $REGION${NC}"
}

# Run main function
main