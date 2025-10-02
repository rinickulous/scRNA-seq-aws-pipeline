process FASTQC {
    tag "$meta.id"
    label 'process_low'
    
    container 'quay.io/biocontainers/fastqc:0.11.9--0'
    
    input:
    tuple val(meta), path(reads)
    
    output:
    tuple val(meta), path("*.zip") , emit: zip
    tuple val(meta), path("*.html"), emit: html
    path "versions.yml"             , emit: versions
    
    when:
    task.ext.when == null || task.ext.when
    
    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    fastqc \\
        $args \\
        --threads $task.cpus \\
        $reads
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqc: \$(fastqc --version | sed -e "s/FastQC v//g")
    END_VERSIONS
    """
}