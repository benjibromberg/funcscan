process PLANTISMASH {
    tag "$meta.id"
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://benjibromberg/plantismash:2.0.4':
        'docker.io/benjibromberg/plantismash:2.0.4' }"

    input:
    tuple val(meta), path(genbank)
    path antismash_db

    output:
    tuple val(meta), path("${meta.id}_plantismash"), emit: results
    path "versions.yml"                            , emit: versions

    script:
    """
    # 0. Redirect temp files to work directory (host-mounted, avoids Docker VM /tmp space issues)
    mkdir -p tmp_dir
    export TMPDIR=\$PWD/tmp_dir

    # 1. Locate system package
    SITE_PACKAGES=\$(python3 -c "import site; print(site.getsitepackages()[0])")

    # 2. Create Shadow Package 'local_pkg/antismash'
    # We use a subdir 'local_pkg' so we can add it to PYTHONPATH
    mkdir -p local_pkg/antismash

    # 3. Symlink everything from system package to our shadow package
    ln -s \$SITE_PACKAGES/antismash/* local_pkg/antismash/

    # 4. Merge 'generic_modules' from system and downloaded databases
    # We cannot simply replace the directory because it contains both code and data.
    # We must create a real directory and link contents from both sources.
    rm local_pkg/antismash/generic_modules
    mkdir local_pkg/antismash/generic_modules
    
    # Link all system generic_modules content first (code + default data)
    ln -s \$SITE_PACKAGES/antismash/generic_modules/* local_pkg/antismash/generic_modules/

    # Iterate over downloaded database subdirectories (e.g., clusterblast, smcogs)
    # and merge them into the shadow package
    for db_dir in \$(ls ${antismash_db}/generic_modules); do
        if [ -L local_pkg/antismash/generic_modules/\$db_dir ]; then
            # If it's a symlink to system dir, convert to real directory to allow merging
            rm local_pkg/antismash/generic_modules/\$db_dir
            mkdir local_pkg/antismash/generic_modules/\$db_dir
            
            # Re-link system files (code)
            ln -s \$SITE_PACKAGES/antismash/generic_modules/\$db_dir/* local_pkg/antismash/generic_modules/\$db_dir/
            
            # Link downloaded database files (force overwrite if collision)
            ln -s -f \$PWD/${antismash_db}/generic_modules/\$db_dir/* local_pkg/antismash/generic_modules/\$db_dir/
            
            # Extract any tar.gz files from the downloaded directory into the shadow directory
            # This is needed because some databases (like clusterblast) might be downloaded as tarballs
            for tarball in \$(ls ${antismash_db}/generic_modules/\$db_dir/*.tar.gz 2>/dev/null); do
                tar -xzf \$tarball -C local_pkg/antismash/generic_modules/\$db_dir/
            done
        fi
    done

    # 5. Set PYTHONPATH so 'import antismash' finds our shadow package
    export PYTHONPATH=\$PWD/local_pkg\${PYTHONPATH:+:\$PYTHONPATH}

    # Handle gzipped input and preserve extension
    if [[ "${genbank}" == *.gz ]]; then
        # Strip .gz extension for the unzipped filename
        INPUT_FILE=\$(basename "${genbank}" .gz)
        gunzip -c ${genbank} > \$INPUT_FILE
    else
        INPUT_FILE=${genbank}
    fi

    # 6. Sanitize ambiguous amino acid codes in GenBank protein translations
    # pplacer (used by the subgroup module) crashes on non-standard residues like J (Leu/Ile),
    # B (Asx), Z (Glx), O (Pyl), U (Sec). Replace them with X (unknown) only within
    # /translation= qualifier blocks to avoid corrupting gene names and other metadata.
    # See: https://github.com/plantismash/plantismash/issues/50
    cat > sanitize_aa.py << 'PYEOF'
import sys
fn = sys.argv[1]
in_translation = False
out_lines = []
with open(fn, 'r') as f:
    for line in f:
        if '/translation="' in line:
            in_translation = True
            line = line.replace('J','X').replace('B','X').replace('Z','X').replace('O','X').replace('U','X')
        elif in_translation:
            if '"' in line:
                in_translation = False
            line = line.replace('J','X').replace('B','X').replace('Z','X').replace('O','X').replace('U','X')
        out_lines.append(line)
with open(fn, 'w') as f:
    f.writelines(out_lines)
PYEOF
    python3 sanitize_aa.py \$INPUT_FILE

    # 7. Run antismash
    # We copy run_antismash.py to current dir so sys.path[0] is '.'
    # This ensures PYTHONPATH (containing local_pkg) takes precedence over site-packages
    cp \$SITE_PACKAGES/run_antismash.py .
    python3 run_antismash.py \\
        --outputfolder ${meta.id}_plantismash \\
        --cpus ${task.cpus} \\
        --taxon plants \\
        ${params.plantismash_clusterblast ? '--clusterblast' : ''} \\
        ${params.plantismash_knownclusterblast ? '--knownclusterblast' : ''} \\
        ${params.plantismash_subgroup ? '' : '--disable_subgroup'} \\
        \$INPUT_FILE

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        plantismash: \$(python3 \$SITE_PACKAGES/run_antismash.py --version | sed 's/antiSMASH //')
    END_VERSIONS
    """
}