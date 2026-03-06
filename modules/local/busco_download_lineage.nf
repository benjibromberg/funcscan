process BUSCO_DOWNLOAD_LINEAGE {
    tag "busco_lineage"
    label 'process_single'

    conda "bioconda::busco=6.0.0"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/41/4137d65ab5b90d2ae4fa9d3e0e8294ddccc287e53ca653bb3c63b8fdb03e882f/data'
        : 'community.wave.seqera.io/library/busco:6.0.0--a9a1426105f81165'}"

    output:
    path "busco_downloads", emit: lineage_dir

    script:
    """
    busco --download ${params.busco_lineage} --download_path busco_downloads
    """
}
