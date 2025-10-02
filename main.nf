#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

/*
========================================================================================
    scRNA-seq Analysis Pipeline with AWS Integration
========================================================================================
*/

// Pipeline version
version = '1.0.0'

// Display help message
params.help = false
if (params.help) {
    helpMessage()
    exit 0
}

// Input/output parameters
params.input = null
params.outdir = "./results"
params.reference = null
params.fasta = null
params.gtf = null
params.genome_name = "custom_genome"

// AWS parameters
params.awsregion = "us-east-1"
params.awsqueue = null

// Validate required parameters
if (!params.input) {
    error "Please provide an input samplesheet with --input"
}

/*
========================================================================================
    IMPORT MODULES DIRECTLY
========================================================================================
*/

include { FASTQC } from './modules/fastqc/main'
include { CELLRANGER_COUNT; CELLRANGER_MKREF } from './modules/cellranger/main'
include { SEURAT_ANALYSIS } from './modules/seurat/main'

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

def helpMessage() {
    log.info """
    =========================================
    scRNA-seq Analysis Pipeline v${version}
    =========================================
    
    Usage:
    nextflow run main.nf --input samplesheet.csv --outdir results
    
    Required parameters:
      --input [file]              Path to input samplesheet CSV
      --outdir [dir]              Output directory (default: ./results)
      
    Reference genome options:
      --reference [dir]           Path to Cell Ranger reference
      OR
      --fasta [file]              Path to genome FASTA file
      --gtf [file]                Path to GTF annotation file
      --genome_name [str]         Name for custom genome (default: custom_genome)
      
    AWS Batch options:
      --awsregion [str]           AWS region (default: us-east-1)
      --awsqueue [str]            AWS Batch queue name
      
    Other options:
      --help                      Show this help message
    """.stripIndent()
}

def checkSamplesheet(samplesheet) {
    Channel
        .fromPath(samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def meta = [:]
            meta.id = row.sample_id
            meta.samples = row.sample_name ?: null
            
            def fastq_path = file(row.fastq_dir)
            if (!fastq_path.exists()) {
                error "Fastq directory does not exist: ${row.fastq_dir}"
            }
            
            return [meta, fastq_path]
        }
}

/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {
    
    log.info """
    =========================================
    scRNA-seq Analysis Pipeline v${version}
    =========================================
    input        : ${params.input}
    outdir       : ${params.outdir}
    reference    : ${params.reference ?: 'Not provided'}
    workDir      : ${workflow.workDir}
    profile      : ${workflow.profile}
    =========================================
    """
    
    // Create input channel from samplesheet
    ch_input = checkSamplesheet(params.input)
    
    // Create channels for version tracking
    ch_versions = Channel.empty()
    
    // Run FastQC
    FASTQC(ch_input)
    ch_versions = ch_versions.mix(FASTQC.out.versions)
    
    // Handle reference
    if (params.reference) {
        ch_cellranger_ref = Channel.fromPath(params.reference)
    } else if (params.fasta && params.gtf) {
        CELLRANGER_MKREF(
            Channel.fromPath(params.fasta),
            Channel.fromPath(params.gtf),
            params.genome_name
        )
        ch_cellranger_ref = CELLRANGER_MKREF.out.reference
        ch_versions = ch_versions.mix(CELLRANGER_MKREF.out.versions)
    } else {
        error "Either --reference or both --fasta and --gtf must be provided"
    }
    
    // Run Cell Ranger Count
    CELLRANGER_COUNT(
        ch_input,
        ch_cellranger_ref
    )
    ch_versions = ch_versions.mix(CELLRANGER_COUNT.out.versions)
    
    // Run Seurat Analysis
    SEURAT_ANALYSIS(
        CELLRANGER_COUNT.out.filtered_matrix
    )
    ch_versions = ch_versions.mix(SEURAT_ANALYSIS.out.versions)
}

workflow.onComplete {
    log.info """
    =========================================
    Pipeline completed at: ${workflow.complete}
    Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Execution duration: ${workflow.duration}
    =========================================
    """.stripIndent()
    
    if (workflow.success) {
        log.info "Results saved to: ${params.outdir}"
    } else {
        log.error "Pipeline execution failed!"
    }
}