#!/bin/bash

# Complete pipeline execution script for scRNA-seq analysis
# This script handles both local and AWS Batch execution

set -e

# Default parameters
PROFILE="docker"
INPUT=""
OUTDIR="./results"
REFERENCE=""
FASTA=""
GTF=""
AWS_QUEUE=""
AWS_REGION="us-east-1"
WORK_DIR=""
RESUME=false
TEST=false

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    -i, --input FILE        Input samplesheet (required)
    -o, --outdir DIR        Output directory (default: ./results)
    -r, --reference DIR     Cell Ranger reference directory
    -f, --fasta FILE        Genome FASTA file (for custom reference)
    -g, --gtf FILE          GTF annotation file (for custom reference)
    -p, --profile PROFILE   Execution profile (docker|singularity|awsbatch)
    -q, --queue QUEUE       AWS Batch queue name (for awsbatch profile)
    -w, --work-dir DIR      Work directory (default: ./work or s3://bucket/work for AWS)
    --region REGION         AWS region (default: us-east-1)
    --resume                Resume previous run
    --test                  Run with test data
    -h, --help              Show this help message

Examples:
    # Local execution with Docker
    $0 -i samplesheet.csv -o results -r /path/to/reference -p docker

    # AWS Batch execution
    $0 -i s3://bucket/samplesheet.csv -o s3://bucket/results -r s3://bucket/reference -p awsbatch -q my-queue

    # Build custom reference and run
    $0 -i samplesheet.csv -f genome.fa -g genes.gtf -o results

    # Run test
    $0 --test
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT="$2"
            shift 2
            ;;
        -o|--outdir)
            OUTDIR="$2"
            shift 2
            ;;
        -r|--reference)
            REFERENCE="$2"
            shift 2
            ;;
        -f|--fasta)
            FASTA="$2"
            shift 2
            ;;
        -g|--gtf)
            GTF="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -q|--queue)
            AWS_QUEUE="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --test)
            TEST=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check Nextflow
    if ! command -v nextflow &> /dev/null; then
        echo -e "${RED}Nextflow is not installed!${NC}"
        echo -e "${YELLOW}Installing Nextflow...${NC}"
        curl -s https://get.nextflow.io | bash
        sudo mv nextflow /usr/local/bin/
    fi
    
    # Check Docker/Singularity based on profile
    if [ "$PROFILE" == "docker" ]; then
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Docker is not installed!${NC}"
            exit 1
        fi
        if ! docker info &> /dev/null; then
            echo -e "${RED}Docker daemon is not running!${NC}"
            exit 1
        fi
    elif [ "$PROFILE" == "singularity" ]; then
        if ! command -v singularity &> /dev/null; then
            echo -e "${RED}Singularity is not installed!${NC}"
            exit 1
        fi
    elif [ "$PROFILE" == "awsbatch" ]; then
        if ! command -v aws &> /dev/null; then
            echo -e "${RED}AWS CLI is not installed!${NC}"
            exit 1
        fi
        if [ -z "$AWS_QUEUE" ]; then
            echo -e "${RED}AWS Batch queue not specified! Use -q option.${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}Prerequisites check passed!${NC}"
}

# Function to run test
run_test() {
    echo -e "${GREEN}Running pipeline with test data...${NC}"
    
    # Create test samplesheet
    cat > test_samplesheet.csv <<EOF
sample_id,sample_name,fastq_dir
test_sample,test_pbmc,./test_data/fastq/
EOF
    
    # Create test data directory structure
    mkdir -p test_data/fastq
    
    echo -e "${YELLOW}Note: Add test FASTQ files to ./test_data/fastq/${NC}"
    
    # Run pipeline
    nextflow run main.nf \
        -profile $PROFILE \
        --input test_samplesheet.csv \
        --outdir test_results \
        -with-report test_results/execution_report.html \
        -with-timeline test_results/execution_timeline.html \
        -with-dag test_results/pipeline_dag.png
}

# Function to build command
build_command() {
    local cmd="nextflow run main.nf"
    
    # Add profile
    cmd="$cmd -profile $PROFILE"
    
    # Add input
    if [ -n "$INPUT" ]; then
        cmd="$cmd --input $INPUT"
    fi
    
    # Add output directory
    cmd="$cmd --outdir $OUTDIR"
    
    # Add reference options
    if [ -n "$REFERENCE" ]; then
        cmd="$cmd --reference $REFERENCE"
    elif [ -n "$FASTA" ] && [ -n "$GTF" ]; then
        cmd="$cmd --fasta $FASTA --gtf $GTF"
    fi
    
    # Add AWS options
    if [ "$PROFILE" == "awsbatch" ]; then
        cmd="$cmd --awsqueue $AWS_QUEUE --awsregion $AWS_REGION"
        
        # Set work directory for AWS
        if [ -z "$WORK_DIR" ]; then
            echo -e "${YELLOW}No work directory specified for AWS Batch. Using default S3 location.${NC}"
            WORK_DIR="s3://scrna-seq-work-$(date +%Y%m%d)/work"
        fi
    fi
    
    # Add work directory
    if [ -n "$WORK_DIR" ]; then
        cmd="$cmd -work-dir $WORK_DIR"
    fi
    
    # Add resume flag
    if [ "$RESUME" = true ]; then
        cmd="$cmd -resume"
    fi
    
    # Add reporting
    cmd="$cmd -with-report ${OUTDIR}/pipeline_info/execution_report.html"
    cmd="$cmd -with-timeline ${OUTDIR}/pipeline_info/execution_timeline.html"
    cmd="$cmd -with-trace ${OUTDIR}/pipeline_info/execution_trace.txt"
    cmd="$cmd -with-dag ${OUTDIR}/pipeline_info/pipeline_dag.html"
    
    echo "$cmd"
}

# Function to run pipeline
run_pipeline() {
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}Running scRNA-seq Pipeline${NC}"
    echo -e "${GREEN}===============================================${NC}"
    
    echo -e "${YELLOW}Configuration:${NC}"
    echo -e "  Profile: ${GREEN}$PROFILE${NC}"
    echo -e "  Input: ${GREEN}$INPUT${NC}"
    echo -e "  Output: ${GREEN}$OUTDIR${NC}"
    if [ -n "$REFERENCE" ]; then
        echo -e "  Reference: ${GREEN}$REFERENCE${NC}"
    elif [ -n "$FASTA" ] && [ -n "$GTF" ]; then
        echo -e "  FASTA: ${GREEN}$FASTA${NC}"
        echo -e "  GTF: ${GREEN}$GTF${NC}"
    fi
    if [ "$PROFILE" == "awsbatch" ]; then
        echo -e "  AWS Queue: ${GREEN}$AWS_QUEUE${NC}"
        echo -e "  AWS Region: ${GREEN}$AWS_REGION${NC}"
        echo -e "  Work Dir: ${GREEN}$WORK_DIR${NC}"
    fi
    echo -e "${GREEN}===============================================${NC}"
    
    # Build command
    local cmd=$(build_command)
    
    echo -e "${YELLOW}Executing command:${NC}"
    echo -e "${GREEN}$cmd${NC}"
    echo ""
    
    # Execute pipeline
    eval $cmd
    
    # Check exit status
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}===============================================${NC}"
        echo -e "${GREEN}Pipeline completed successfully!${NC}"
        echo -e "${GREEN}Results saved to: $OUTDIR${NC}"
        echo -e "${GREEN}===============================================${NC}"
    else
        echo -e "${RED}===============================================${NC}"
        echo -e "${RED}Pipeline failed!${NC}"
        echo -e "${RED}Check the logs for details.${NC}"
        echo -e "${RED}===============================================${NC}"
        exit 1
    fi
}

# Main execution
main() {
    # Show header
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}scRNA-seq Analysis Pipeline Runner${NC}"
    echo -e "${GREEN}===============================================${NC}"
    
    # Check if test mode
    if [ "$TEST" = true ]; then
        check_prerequisites
        run_test
        exit 0
    fi
    
    # Validate required parameters
    if [ -z "$INPUT" ]; then
        echo -e "${RED}Error: Input samplesheet is required!${NC}"
        usage
        exit 1
    fi
    
    # Validate reference inputs
    if [ -z "$REFERENCE" ] && ([ -z "$FASTA" ] || [ -z "$GTF" ]); then
        echo -e "${RED}Error: Either --reference or both --fasta and --gtf must be provided!${NC}"
        usage
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Run pipeline
    run_pipeline
}

# Run main function
main