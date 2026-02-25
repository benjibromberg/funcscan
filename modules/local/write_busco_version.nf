process WRITE_BUSCO_VERSION {
    tag "busco_version"
    label 'process_single'

    conda "conda-forge::sed=4.7"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/41/4137d65ab5b90d2ae4fa9d3e0e8294ddccc287e53ca653bb3c63b8fdb03e882f/data'
        : 'community.wave.seqera.io/library/busco:6.0.0--a9a1426105f81165'}"

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
