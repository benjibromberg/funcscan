process BIGSCAPE {
    label 'process_high'
    container 'quay.io/biocontainers/bigscape:2.0.2--pyhdfd78af_0'

    input:
    path "all_bgcs/*"
    path pfam_db

    output:
    path "bigscape_results", emit: results
    path "versions.yml"    , emit: versions

    script:
    """
    bigscape cluster \\
        -i all_bgcs \\
        -o bigscape_results \\
        -p ${pfam_db} \\
        --mix \\
        --cores ${task.cpus}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bigscape: \$(bigscape --version 2>&1 | sed 's/BiG-SCAPE //')
    END_VERSIONS
    """
}