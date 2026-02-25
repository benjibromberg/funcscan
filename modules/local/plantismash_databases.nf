
process PLANTISMASH_DATABASES {
    tag "download_databases"
    label 'process_medium'

    cpus 2
    memory '4 GB'
    time '1h'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://benjibromberg/plantismash:2.0.4':
        'docker.io/benjibromberg/plantismash:2.0.4' }"

    output:
    path "antismash", emit: db // Output the downloaded database directory structure

    script:
    """
    # Run the download script.
    # It uses os.getcwd() to determine where to create 'antismash/generic_modules'.
    # However, it expects 'smcogs/smcogs.hmm' to be present to run hmmpress on it.
    # Since we are starting empty, we must copy it from the system package first.
    
    SITE_PACKAGES=\$(python3 -c "import site; print(site.getsitepackages()[0])")
    mkdir -p antismash/generic_modules/smcogs
    
    # Copy from system location. Use -L to dereference symlinks if any.
    cp -L \$SITE_PACKAGES/antismash/generic_modules/smcogs/smcogs.hmm antismash/generic_modules/smcogs/
    
    # Ensure write permissions for the directory so hmmpress can write auxiliary files
    chmod -R u+w antismash/generic_modules/smcogs
    
    plantismash_download_databases --overwrite no
    """
}
