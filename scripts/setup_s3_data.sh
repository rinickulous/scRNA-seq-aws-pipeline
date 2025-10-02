#!/bin/bash

# Script to set up S3 buckets and upload test data for the pipeline

set -e

# Configuration
REGION=${AWS_REGION:-"us-east-1"}
DATA_BUCKET="scrna-seq-data-$(date +%Y%m%d)"
WORK_BUCKET="scrna-seq-work-$(date +%Y%m%d)"
RESULTS_BUCKET="scrna-seq-results-$(date +%Y%m%d)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Setting up S3 buckets for scRNA-seq pipeline${NC}"

# Function to create S3 bucket
create_bucket() {
    local bucket=$1
    
    if aws s3 ls "s3://$bucket" 2>/dev/null; then
        echo -e "${YELLOW}Bucket $bucket already exists${NC}"
    else
        echo -e "${GREEN}Creating bucket: $bucket${NC}"
        if [ "$REGION" == "us-east-1" ]; then
            aws s3 mb "s3://$bucket" --region $REGION
        else
            aws s3api create-bucket \
                --bucket $bucket \
                --region $REGION \
                --create-bucket-configuration LocationConstraint=$REGION
        fi
    fi
}

# Function to download test data
download_test_data() {
    echo -e "${YELLOW}Downloading test data...${NC}"
    
    # Create temporary directory for test data
    mkdir -p /tmp/scrna-test-data
    cd /tmp/scrna-test-data
    
    # Download small test dataset from 10x Genomics
    # Using pbmc_1k_v3 dataset as example
    echo -e "${GREEN}Downloading PBMC 1k test dataset...${NC}"
    
    if [ ! -f "pbmc_1k_v3_fastqs.tar" ]; then
        wget -q https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_1k_v3/pbmc_1k_v3_fastqs.tar
        tar -xf pbmc_1k_v3_fastqs.tar
    fi
    
    # Download reference genome (small version for testing)
    echo -e "${GREEN}Downloading reference genome...${NC}"
    
    if [ ! -f "refdata-gex-GRCh38-2020-A.tar.gz" ]; then
        # Note: This is a large file. For testing, you might want to use a smaller reference
        echo -e "${YELLOW}Note: Full reference genome is large (~11GB).${NC}"
        echo -e "${YELLOW}For testing, consider using a smaller reference or pre-built one.${NC}"
        # wget -q https://cf.10xgenomics.com/supp/cell-exp/refdata-gex-GRCh38-2020-A.tar.gz
        # tar -xzf refdata-gex-GRCh38-2020-A.tar.gz
    fi
}

# Function to upload data to S3
upload_data() {
    echo -e "${GREEN}Uploading test data to S3...${NC}"
    
    # Upload FASTQ files
    if [ -d "pbmc_1k_v3_fastqs" ]; then
        echo -e "${GREEN}Uploading FASTQ files...${NC}"
        aws s3 sync pbmc_1k_v3_fastqs/ "s3://$DATA_BUCKET/fastq/sample1/" \
            --region $REGION
    fi
    
    # Upload reference if it exists
    if [ -d "refdata-gex-GRCh38-2020-A" ]; then
        echo -e "${GREEN}Uploading reference genome...${NC}"
        aws s3 sync refdata-gex-GRCh38-2020-A/ "s3://$DATA_BUCKET/reference/GRCh38/" \
            --region $REGION
    fi
    
    # Create and upload samplesheet
    cat > samplesheet.csv <<EOF
sample_id,sample_name,fastq_dir
pbmc_1k,pbmc_1k_v3,s3://$DATA_BUCKET/fastq/sample1/
EOF
    
    aws s3 cp samplesheet.csv "s3://$DATA_BUCKET/samplesheet.csv" --region $REGION
}

# Function to set up bucket policies
setup_bucket_policies() {
    echo -e "${YELLOW}Setting up bucket policies...${NC}"
    
    # Create lifecycle policy for work bucket (delete after 7 days)
    cat > /tmp/lifecycle-policy.json <<EOF
{
    "Rules": [
        {
            "Id": "DeleteWorkFiles",
            "Status": "Enabled",
            "Expiration": {
                "Days": 7
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket $WORK_BUCKET \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json \
        --region $REGION 2>/dev/null || true
    
    echo -e "${GREEN}Lifecycle policy applied to work bucket${NC}"
}

# Function to create Nextflow config with bucket names
create_config() {
    echo -e "${GREEN}Creating Nextflow configuration with S3 paths...${NC}"
    
    cat > aws.config <<EOF
// AWS S3 Configuration
params {
    // S3 paths
    input = "s3://$DATA_BUCKET/samplesheet.csv"
    outdir = "s3://$RESULTS_BUCKET/results"
    reference = "s3://$DATA_BUCKET/reference/GRCh38"
    
    // AWS settings
    awsregion = "$REGION"
    awsqueue = "scrna-seq-job-queue"
}

// Work directory
workDir = "s3://$WORK_BUCKET/work"

// AWS Batch executor
process.executor = 'awsbatch'
process.queue = params.awsqueue

// AWS region
aws.region = params.awsregion
aws.batch.cliPath = '/usr/local/bin/aws'
EOF
    
    echo -e "${GREEN}Configuration saved to aws.config${NC}"
}

# Main execution
main() {
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}S3 Setup for scRNA-seq Pipeline${NC}"
    echo -e "${GREEN}===============================================${NC}"
    
    # Create buckets
    create_bucket $DATA_BUCKET
    create_bucket $WORK_BUCKET
    create_bucket $RESULTS_BUCKET
    
    # Download and upload test data
    read -p "Do you want to download and upload test data? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        download_test_data
        upload_data
    fi
    
    # Set up bucket policies
    setup_bucket_policies
    
    # Create config file
    create_config
    
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}S3 setup complete!${NC}"
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${YELLOW}S3 Buckets created:${NC}"
    echo -e "  Data: ${GREEN}s3://$DATA_BUCKET${NC}"
    echo -e "  Work: ${GREEN}s3://$WORK_BUCKET${NC}"
    echo -e "  Results: ${GREEN}s3://$RESULTS_BUCKET${NC}"
    echo -e ""
    echo -e "${YELLOW}Configuration file created: ${GREEN}aws.config${NC}"
    echo -e ""
    echo -e "${YELLOW}To run the pipeline:${NC}"
    echo -e "${GREEN}nextflow run main.nf -c aws.config -profile awsbatch${NC}"
}

# Run main
main