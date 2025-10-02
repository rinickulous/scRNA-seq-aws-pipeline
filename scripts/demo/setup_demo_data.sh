#!/bin/bash

# Quick demo setup for scRNA-seq pipeline
# Downloads 10X PBMC 3k dataset for testing

set -e

echo "Setting up demo data for scRNA-seq pipeline..."

# Create demo directory
mkdir -p data/demo

# Download 10X PBMC 3k dataset (small subset for demo)
echo "Downloading 10X PBMC 3k demo data..."

# Sample 1 - subset of PBMC 3k (R1 and R2)
curl -o data/demo/pbmc_3k_R1_001.fastq.gz \
    "https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_3k/pbmc_3k_fastqs.tar" &

# Wait for download and extract a small subset
echo "Processing demo files..."

# Create small test FASTQ files (first 10000 reads)
echo "Creating small test files for demo..."

# Generate small demo FASTQ files
cat > data/demo/create_test_fastqs.py << 'EOF'
#!/usr/bin/env python3
import gzip
import os

def create_small_fastq(output_path, read_type, num_reads=5000):
    """Create a small demo FASTQ file"""
    
    if read_type == "R1":
        # Typical 10X R1: 28bp (16bp cell barcode + 12bp UMI)
        sequences = [
            "AAACCTGAGAAGGCCTGTCAGATC",
            "AAACCTGAGACCTTTGACGTGAAT", 
            "AAACCTGAGCATCATCAGTGACAG",
            "AAACCTGAGGCATGTGCAAGATGC"
        ]
        length = 28
    else:  # R2
        # Typical 10X R2: longer reads with actual transcript sequence
        sequences = [
            "TTTCCTCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGC",
            "AGCTGGCCGAGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGC",
            "GCCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGC",
            "CTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTG"
        ]
        length = 70
    
    with gzip.open(output_path, 'wt') as f:
        for i in range(num_reads):
            seq_idx = i % len(sequences)
            f.write(f"@DEMO_READ_{i+1}_{read_type}\n")
            f.write(f"{sequences[seq_idx]}\n")
            f.write(f"+\n")
            f.write(f"{'I' * length}\n")  # High quality scores
    
    print(f"Created {output_path} with {num_reads} reads")

# Create demo files
create_small_fastq("data/demo/demo_sample_R1_001.fastq.gz", "R1")
create_small_fastq("data/demo/demo_sample_R2_001.fastq.gz", "R2")

print("Demo FASTQ files created successfully!")
EOF

python3 data/demo/create_test_fastqs.py

# Create demo samplesheet
cat > data/demo/samplesheet.csv << EOF
sample_id,fastq_1,fastq_2,expected_cells
demo_sample,data/demo/demo_sample_R1_001.fastq.gz,data/demo/demo_sample_R2_001.fastq.gz,1000
EOF

# Upload to S3 if AWS CLI is available
if command -v aws &> /dev/null; then
    echo "Uploading demo data to S3..."
    aws s3 cp data/demo/ s3://scrna-pipeline-nwhite-input/demo/ --recursive
    aws s3 cp data/demo/samplesheet.csv s3://scrna-pipeline-nwhite-input/
    echo "Demo data uploaded to S3!"
else
    echo "AWS CLI not found. Demo data created locally."
    echo "To upload manually after AWS setup:"
    echo "aws s3 cp data/demo/ s3://scrna-pipeline-nwhite-input/demo/ --recursive"
fi

echo ""
echo "Demo setup complete!"
echo "Local files:"
echo "  - data/demo/demo_sample_R1_001.fastq.gz"
echo "  - data/demo/demo_sample_R2_001.fastq.gz" 
echo "  - data/demo/samplesheet.csv"
echo ""
echo "Next steps:"
echo "1. Configure AWS CLI: aws configure"
echo "2. Test pipeline: nextflow run workflows/main.nf -profile test"
echo "3. AWS test: nextflow run workflows/main.nf -profile aws --input s3://scrna-pipeline-nwhite-input/samplesheet.csv"