process CELLRANGER_COUNT {
    tag "$meta.id"
    label 'process_high'

    conda (params.enable_conda ? "bioconda::cellranger=7.1.0" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/cellranger:7.1.0--pl5321h9ee0642_0' :
        'quay.io/biocontainers/cellranger:7.1.0--pl5321h9ee0642_0' }"

    input:
    tuple val(meta), path(reads)
    path reference

    output:
    tuple val(meta), path("${meta.id}/outs/"), emit: outs
    tuple val(meta), path("${meta.id}/outs/metrics_summary.csv"), emit: metrics
    tuple val(meta), path("${meta.id}/outs/web_summary.html"), emit: report
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def reference_name = reference ? "--transcriptome=${reference}" : "--transcriptome=/opt/refdata-gex-GRCh38-2020-A"
    def chemistry = meta.chemistry ? "--chemistry=${meta.chemistry}" : "--chemistry=auto"
    def expected_cells = meta.expected_cells ? "--expect-cells=${meta.expected_cells}" : ""
    def force_cells = meta.force_cells ? "--force-cells=${meta.force_cells}" : ""
    
    """
    # Create fastq directory structure expected by cellranger
    mkdir -p fastqs
    
    # Create symbolic links with proper 10X naming convention
    ln -s \$(readlink -f ${reads[0]}) fastqs/${meta.id}_S1_L001_R1_001.fastq.gz
    ln -s \$(readlink -f ${reads[1]}) fastqs/${meta.id}_S1_L001_R2_001.fastq.gz
    
    cellranger count \\
        --id=${meta.id} \\
        --fastqs=fastqs \\
        --sample=${meta.id} \\
        $reference_name \\
        $chemistry \\
        $expected_cells \\
        $force_cells \\
        --localcores=${task.cpus} \\
        --localmem=\$((\${task.memory.toGiga()} - 2)) \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellranger: \$(echo \$(cellranger --version 2>&1) | sed 's/^.*[^0-9]\\([0-9]*\\.[0-9]*\\.[0-9]*\\).*\$/\\1/' )
    END_VERSIONS
    """

    stub:
    """
    mkdir -p ${meta.id}/outs/filtered_feature_bc_matrix
    touch ${meta.id}/outs/web_summary.html
    touch ${meta.id}/outs/metrics_summary.csv
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellranger: \$(echo \$(cellranger --version 2>&1) | sed 's/^.*[^0-9]\\([0-9]*\\.[0-9]*\\.[0-9]*\\).*\$/\\1/' )
    END_VERSIONS
    """
}