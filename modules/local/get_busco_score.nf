
process GET_BUSCO_SCORE {
    tag "$meta.id"
    label 'process_single'
    
    // Use python or basic utility container
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9':
        'docker.io/python:3.9' }"

    input:
    tuple val(meta), path(short_summary_json)

    output:
    tuple val(meta), stdout, emit: score

    script:
    """
    # Extract the 'C' score from the results block
    # JSON format: "Complete percentage": 99.6
    # Flexible grep approach to handle potential whitespace variations
    grep -o '"Complete percentage":\\s*[0-9.]*' ${short_summary_json} | cut -d':' -f2 | tr -d ' ' | tr -d '\n'
    """
}
