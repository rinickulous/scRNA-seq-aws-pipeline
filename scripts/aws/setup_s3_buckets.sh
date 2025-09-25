#!/bin/bash

# Setup S3 buckets for scRNA-seq pipeline
# Usage: ./setup_s3_buckets.sh [bucket_prefix]

set -e

# Default bucket prefix - change this to your preferred name
BUCKET_PREFIX=${1:-"scrna-pipeline-$(whoami)"}
REGION=${AWS_DEFAULT_REGION:-"us-east-1"}

echo "Setting up S3 buckets with prefix: ${BUCKET_PREFIX}"
echo "Region: ${REGION}"

# Create buckets
INPUT_BUCKET="${BUCKET_PREFIX}-input"
OUTPUT_BUCKET="${BUCKET_PREFIX}-output"
WORK_BUCKET="${BUCKET_PREFIX}-work"

echo "Creating S3 buckets..."

# Create input bucket
if aws s3 ls "s3://${INPUT_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating input bucket: ${INPUT_BUCKET}"
    aws s3 mb "s3://${INPUT_BUCKET}" --region ${REGION}
else
    echo "Input bucket already exists: ${INPUT_BUCKET}"
fi

# Create output bucket
if aws s3 ls "s3://${OUTPUT_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating output bucket: ${OUTPUT_BUCKET}"
    aws s3 mb "s3://${OUTPUT_BUCKET}" --region ${REGION}
else
    echo "Output bucket already exists: ${OUTPUT_BUCKET}"
fi

# Create work bucket for Nextflow
if aws s3 ls "s3://${WORK_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating work bucket: ${WORK_BUCKET}"
    aws s3 mb "s3://${WORK_BUCKET}" --region ${REGION}
else
    echo "Work bucket already exists: ${WORK_BUCKET}"
fi

# Set up bucket policies for public read access (optional)
echo "Setting up bucket versioning..."
aws s3api put-bucket-versioning --bucket ${OUTPUT_BUCKET} --versioning-configuration Status=Enabled

# Create lifecycle policy to clean up work directory
cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "DeleteOldWorkFiles",
            "Status": "Enabled",
            "Filter": {"Prefix": "work/"},
            "Expiration": {
                "Days": 30
            }
        }
    ]
}
EOF

aws s3api put-bucket-lifecycle-configuration --bucket ${WORK_BUCKET} --lifecycle-configuration file:///tmp/lifecycle-policy.json

echo ""
echo "S3 buckets created successfully!"
echo "Input bucket:  s3://${INPUT_BUCKET}"
echo "Output bucket: s3://${OUTPUT_BUCKET}"
echo "Work bucket:   s3://${WORK_BUCKET}"
echo ""
echo "Update your pipeline configuration:"
echo "  --input s3://${INPUT_BUCKET}/samplesheet.csv"
echo "  --outdir s3://${OUTPUT_BUCKET}/results/"
echo "  Or update config/aws.config workDir to: s3://${WORK_BUCKET}/work/"
echo ""
echo "Next steps:"
echo "1. Upload your data: ./scripts/aws/data_upload.sh <local_path> s3://${INPUT_BUCKET}/"
echo "2. Run pipeline: nextflow run workflows/main.nf -profile aws"