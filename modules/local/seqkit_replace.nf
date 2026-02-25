
process SEQKIT_REPLACE {
    tag "$meta.id"
    label 'process_low'
    
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/seqkit:2.9.0--h9ee0642_0':
        'biocontainers/seqkit:2.9.0--h9ee0642_0' }"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${prefix}.faa"), emit: fasta
    path "versions.yml"                   , emit: versions

    script:
    prefix = task.ext.prefix ?: "${meta.id}_clean"
    """
    # Replace whitespace and everything after it with nothing (keep only ID)
    # or user specified re. 
    # Default behavior for Plant Mode: Clean headers to just ID to avoid AMPlify errors.
    seqkit replace -p "\\s.+" -r "" ${fasta} > ${prefix}.faa
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: \$(seqkit version | cut -d' ' -f2)
    END_VERSIONS
    """
}
