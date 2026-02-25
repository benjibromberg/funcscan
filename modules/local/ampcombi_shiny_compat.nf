process AMPCOMBI_SHINY_COMPAT {
    tag "ampcombi2"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ampcombi:2.0.1--pyhdfd78af_0':
        'biocontainers/ampcombi:2.0.1--pyhdfd78af_0' }"

    input:
    path(input_tsv)

    output:
    path("Ampcombi_summary_cluster.tsv")                   , emit: cluster_tsv
    path("launch_ampcombi_viz.sh")                         , emit: viz_launcher
    path "versions.yml"                                    , emit: versions

    script:
    """
    python -c "
import pandas as pd
df = pd.read_csv('${input_tsv}', sep='\\\\t')
tools = ['prob_ampir','prob_ampgram','prob_neubi','prob_amptransformer','HMM_model','prob_amplify','prob_macrel', 'aa_sequence']
for t in tools:
    if t not in df.columns:
        df[t] = 0.0 if t != 'aa_sequence' else ''

df.to_csv('Ampcombi_summary_cluster.tsv', sep='\\\\t', index=False)
"

    cp \$(which launch_ampcombi_viz.sh) launch_ampcombi_viz.sh

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python --version | sed 's/Python //g')
    pandas: \$(python -c "import pandas; print(pandas.__version__)")
END_VERSIONS
    """
}
