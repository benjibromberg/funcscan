
process COLLECT_GENBANKS {
    label 'process_low'

    input:
    path bgc_dirs

    output:
    path "all_bgcs", emit: bgc_dir

    script:
    """
    mkdir all_bgcs
    # Find all .gbk files in the input directories and copy them to the flattened directory
    # Use -n to avoid overwriting if name collisions occur (though meta.id prefix should prevent this)
    find ${bgc_dirs} -name "*.gbk" -exec cp -n {} all_bgcs/ \\;
    """
}
