#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

log.info """
scRNA-seq Pipeline Demo
=======================
Input:  ${params.input ?: 'Not specified'}
Output: ${params.outdir ?: './results'}
"""

workflow {
    log.info "Pipeline started successfully!"
    log.info "Demo files: ${file('data/demo/').listFiles()}"
}
