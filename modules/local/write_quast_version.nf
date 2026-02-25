process WRITE_QUAST_VERSION {
    tag "quast_version"
    label 'process_single'

    conda "conda-forge::sed=4.7"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/a5/a515d04307ea3e0178af75132105cd36c87d0116c6f9daecf81650b973e870fd/data' :
        'community.wave.seqera.io/library/quast:5.3.0--755a216045b6dbdd' }"

    input:
    tuple val(process_name), val(tool_name), val(version_string)

    output:
    path "versions.yml", emit: versions

    script:
    """
    cat <<-END_VERSIONS > versions.yml
    "${process_name}":
        ${tool_name}: ${version_string}
    END_VERSIONS
    """

    stub:
    """
    touch versions.yml
    """
}
