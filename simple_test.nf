#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

process test {
    executor 'awsbatch'
    queue 'scrna-seq-job-queue'
    container 'amazonlinux:2'
    
    script:
    """
    echo "AWS Batch is working"
    """
}

workflow {
    test()
}
