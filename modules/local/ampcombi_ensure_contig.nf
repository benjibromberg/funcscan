process AMPCOMBI_ENSURE_CONTIG {
    tag "$meta.id"
    label 'process_single'

    conda "conda-forge::sed=4.7"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ampcombi:2.0.1--pyhdfd78af_0':
        'biocontainers/ampcombi:2.0.1--pyhdfd78af_0' }"

    input:
    tuple val(meta), path(tsv)

    output:
    tuple val(meta), path("*_fixed.tsv"), emit: tsv
    path "versions.yml"                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    if [ ! -z "\$(head -n 1 ${tsv} | grep -w CDS_id)" ] && ! head -n 1 ${tsv} | grep -qw "contig_id"; then
        awk 'BEGIN{FS=OFS="\\t"} NR==1 {for(i=1;i<=NF;i++) if(\$i=="CDS_id") col=i; print \$0, "contig_id"} NR>1 {print \$0, \$col}' ${tsv} > ${prefix}_fixed.tsv
    else
        cp ${tsv} ${prefix}_fixed.tsv
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ampcombi: 2.0.1
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fixed.tsv
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ampcombi: 2.0.1
    END_VERSIONS
    """
}
