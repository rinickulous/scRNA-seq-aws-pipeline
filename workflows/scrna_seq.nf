#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

// Import modules
include { FASTQC } from '../modules/fastqc/main'
include { CELLRANGER_COUNT; CELLRANGER_MKREF } from '../modules/cellranger/main'
include { SEURAT_ANALYSIS } from '../modules/seurat/main'

workflow SCRNA_SEQ {
    take:
    ch_input      // channel: [ val(meta), [ fastq_files ] ]
    ch_reference  // channel: path to reference or null
    ch_fasta      // channel: path to fasta (if building reference)
    ch_gtf        // channel: path to gtf (if building reference)
    
    main:
    ch_versions = Channel.empty()
    
    // Run FastQC
    FASTQC(ch_input)
    ch_versions = ch_versions.mix(FASTQC.out.versions)
    
    // Handle reference - either use provided or build it
    if (params.reference) {
        ch_cellranger_ref = Channel.fromPath(params.reference)
    } else if (params.fasta && params.gtf) {
        CELLRANGER_MKREF(
            ch_fasta,
            ch_gtf,
            params.genome_name ?: "custom_genome"
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
    
    emit:
    fastqc_html    = FASTQC.out.html
    fastqc_zip     = FASTQC.out.zip
    matrix         = CELLRANGER_COUNT.out.filtered_matrix
    metrics        = CELLRANGER_COUNT.out.metrics
    web_summary    = CELLRANGER_COUNT.out.html
    seurat_object  = SEURAT_ANALYSIS.out.seurat_object
    umap           = SEURAT_ANALYSIS.out.umap
    markers        = SEURAT_ANALYSIS.out.markers
    versions       = ch_versions
}