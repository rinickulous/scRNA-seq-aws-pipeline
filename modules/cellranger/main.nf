process CELLRANGER_COUNT {
    tag "$meta.id"
    label 'process_high'
    
    container 'nfcore/cellranger:7.1.0'
    
    input:
    tuple val(meta), path(fastq_dir)
    path reference
    
    output:
    tuple val(meta), path("${prefix}/outs/filtered_feature_bc_matrix"), emit: filtered_matrix
    tuple val(meta), path("${prefix}/outs/raw_feature_bc_matrix")     , emit: raw_matrix
    tuple val(meta), path("${prefix}/outs/metrics_summary.csv")       , emit: metrics
    tuple val(meta), path("${prefix}/outs/web_summary.html")          , emit: html
    tuple val(meta), path("${prefix}/outs/cloupe.cloupe")             , emit: cloupe, optional: true
    path "versions.yml"                                                , emit: versions
    
    when:
    task.ext.when == null || task.ext.when
    
    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def sample_arg = meta.samples ? "--sample ${meta.samples}" : ""
    """
    cellranger count \\
        --id=${prefix} \\
        --transcriptome=${reference} \\
        --fastqs=${fastq_dir} \\
        ${sample_arg} \\
        --localcores=${task.cpus} \\
        --localmem=${task.memory.toGiga()} \\
        $args
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellranger: \$(cellranger -V | sed -e 's/cellranger cellranger-//')
    END_VERSIONS
    """
}

process CELLRANGER_MKREF {
    tag "$genome_name"
    label 'process_high'
    
    container 'nfcore/cellranger:7.1.0'
    
    input:
    path fasta
    path gtf
    val genome_name
    
    output:
    path "${genome_name}", emit: reference
    path "versions.yml"  , emit: versions
    
    script:
    def args = task.ext.args ?: ''
    """
    cellranger mkref \\
        --genome=${genome_name} \\
        --fasta=${fasta} \\
        --genes=${gtf} \\
        --nthreads=${task.cpus} \\
        $args
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellranger: \$(cellranger -V | sed -e 's/cellranger cellranger-//')
    END_VERSIONS
    """
}