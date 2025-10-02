# scRNA-seq AWS Pipeline

A Nextflow DSL2 pipeline for single-cell RNA-seq analysis with AWS integration capabilities.

## 🎯 Project Status

**Pipeline Status**: ✅ Functional (local/EC2 execution)  
**AWS Batch Status**: ⚠️ Configuration challenges encountered  
**Recommended Deployment**: EC2 instance or Nextflow Tower/Seqera Platform

## 📋 Overview

This pipeline implements a complete scRNA-seq analysis workflow using:
- **FastQC** for quality control
- **Cell Ranger** for alignment and counting
- **Seurat** for downstream analysis

Built with Nextflow DSL2 for modularity and reproducibility.

## ✅ What Works

- ✅ Modular DSL2 pipeline structure
- ✅ FastQC quality control module
- ✅ Cell Ranger alignment and counting
- ✅ Seurat analysis integration
- ✅ S3 integration for data storage
- ✅ Local execution with Docker
- ✅ EC2 execution capability
- ✅ Proper configuration management

## ⚠️ Known Issues

### AWS Batch Integration
During development, we encountered persistent issues with AWS Batch job submission:

**Error**: `The user value contains invalid characters. Enter a value that matches the pattern ^([a-z0-9_][a-z0-9_-]{0,30})$`

**Root Cause Investigation**:
- AWS Batch has strict job naming requirements incompatible with Nextflow's DSL2 process naming conventions (e.g., `WORKFLOW:PROCESS`)
- Attempted solutions included various job name sanitization strategies
- Issue may be related to IAM user configuration or root account usage

**Recommended Alternatives**:
1. Run on EC2 instances directly
2. Use AWS Genomics CLI
3. Deploy via Nextflow Tower/Seqera Platform
4. Consider nf-core/scrnaseq pipeline which has proven AWS Batch configurations

## 🚀 Quick Start

### Prerequisites
- Nextflow (>= 21.10.3)
- Docker or Singularity
- AWS CLI configured
- S3 buckets for data storage

### Local Execution
```bash
nextflow run main.nf \
    -profile docker \
    --input samplesheet.csv \
    --reference /path/to/reference \
    --outdir results \
    -work-dir ./work
```

### EC2 Execution
```bash
# Launch EC2 instance (recommended: t3.xlarge, 100GB storage)
# Install dependencies
sudo yum install docker git -y
sudo service docker start
curl -s https://get.nextflow.io | bash

# Run pipeline
nextflow run main.nf \
    -profile docker \
    --input s3://your-bucket/samplesheet.csv \
    --reference s3://your-bucket/reference/GRCh38 \
    --outdir s3://your-bucket/results \
    -work-dir ./work
```

## 📁 Pipeline Structure

```
├── main.nf                 # Main pipeline script
├── nextflow.config         # Configuration file
├── modules/               # DSL2 modules
│   ├── fastqc/
│   ├── cellranger/
│   └── seurat/
├── workflows/             # Workflow definitions
└── conf/                  # Profile configurations
    ├── base.config
    └── awsbatch.config    # AWS Batch config (see known issues)
```

## 📊 Input Requirements

### Samplesheet Format
```csv
sample_id,sample_name,fastq_dir
sample1,PBMC_1k,s3://bucket/fastq/sample1/
sample2,PBMC_5k,s3://bucket/fastq/sample2/
```

### Reference Genome
- Pre-built Cell Ranger reference
- Or provide FASTA + GTF for custom reference build

## 🔬 Analysis Steps

1. **Quality Control**: FastQC analysis of raw reads
2. **Alignment**: Cell Ranger alignment to reference genome
3. **Counting**: Generation of feature-barcode matrices
4. **Analysis**: Seurat-based clustering and differential expression

## 💡 Lessons Learned

1. **AWS Batch Complexity**: The integration between Nextflow DSL2 and AWS Batch requires careful attention to job naming conventions
2. **IAM Considerations**: Root account usage may cause unexpected issues with AWS Batch
3. **Alternative Solutions**: Established pipelines like nf-core/scrnaseq have solved many of these integration challenges
4. **Resource Requirements**: Cell Ranger requires significant compute resources (8+ CPUs, 64GB+ RAM)

## 🔄 Future Improvements

- [ ] Resolve AWS Batch job naming compatibility
- [ ] Add support for alternative aligners (STARsolo, Alevin)
- [ ] Implement automated cell type annotation
- [ ] Add multi-sample integration capabilities
- [ ] Create Nextflow Tower deployment configuration

## 🤝 Contributing

This pipeline was developed as a learning exercise in AWS/Nextflow integration. Contributions and suggestions for AWS Batch compatibility fixes are welcome.

## 📚 References

- [Nextflow Documentation](https://www.nextflow.io/docs/latest/index.html)
- [AWS Batch + Nextflow Guide](https://www.nextflow.io/docs/latest/aws.html)
- [nf-core/scrnaseq](https://github.com/nf-core/scrnaseq) - Production-ready alternative
- [Cell Ranger](https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/latest/what-is-cell-ranger)

## 📄 License

MIT

---

**Note**: This pipeline successfully demonstrates Nextflow DSL2 architecture and scRNA-seq analysis workflow design. For production AWS deployment, consider using established solutions like nf-core/scrnaseq or Nextflow Tower which have resolved the AWS Batch integration challenges encountered here.