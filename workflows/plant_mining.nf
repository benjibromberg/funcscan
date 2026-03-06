/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { BUSCO_BUSCO as BUSCO_QC   } from '../modules/nf-core/busco/busco/main'
include { BUSCO_DOWNLOAD_LINEAGE   } from '../modules/local/busco_download_lineage'
include { QUAST                   } from '../modules/nf-core/quast/main'
include { WRITE_QUAST_VERSION     } from '../modules/local/write_quast_version'
include { WRITE_BUSCO_VERSION     } from '../modules/local/write_busco_version'
include { PLANTISMASH             } from '../modules/local/plantismash'
include { PLANTISMASH_DATABASES   } from '../modules/local/plantismash_databases'
include { BIGSCAPE                } from '../modules/local/bigscape'
include { COLLECT_GENBANKS        } from '../modules/local/collect_genbanks'
include { GET_BUSCO_SCORE         } from '../modules/local/get_busco_score'
include { SEQKIT_REPLACE          } from '../modules/local/seqkit_replace'
include { MULTIQC                 } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { paramsSummaryMultiqc    } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML  } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText  } from '../subworkflows/local/utils_nfcore_funcscan_pipeline'
include { GUNZIP                  } from '../modules/nf-core/gunzip/main'
include { AMP                     } from '../subworkflows/local/amp'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PLANT_MINING {

    take:
    samplesheet // channel: [ val(meta), [ genome_gbk, proteome_faa ] ]

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // -----------------------------------------------------------------------
    // 1. DATA PREPARATION
    // -----------------------------------------------------------------------
    // Split input into separate channels for Genome (BGCs) and Proteome (QC/AMPs)
    // samplesheet emits [ meta, fasta, faa, gbk ]
    ch_genomes   = samplesheet.map { meta, fasta, faa, gbk -> [ meta, fasta ] }
    ch_proteomes = samplesheet.map { meta, fasta, faa, gbk -> [ meta, faa ] }

    // Sanitize Proteome Headers (critical for AMPlify etc)
    SEQKIT_REPLACE(ch_proteomes)
    ch_clean_proteomes = SEQKIT_REPLACE.out.fasta
    ch_versions = ch_versions.mix(SEQKIT_REPLACE.out.versions)

    // -----------------------------------------------------------------------
    // 2. QUALITY CONTROL
    // -----------------------------------------------------------------------
    
    // 2A. BUSCO on Proteins
    // Download BUSCO lineage database once, then share with all BUSCO_QC tasks
    BUSCO_DOWNLOAD_LINEAGE ()
    // Mode 'proteins' is much faster than genome mode for checking gene set completeness
    BUSCO_QC ( ch_clean_proteomes, "proteins", params.busco_lineage, BUSCO_DOWNLOAD_LINEAGE.out.lineage_dir, [], [] )
    
    // TODO: nf-core is migrating module version emissions to use Nextflow's new `topic: versions` system, 
    // which emits a tuple of `[process, component, version]` rather than a standard `versions.yml` file.
    // However, the `softwareVersionsToYAML` script used in this pipeline's template has not yet been 
    // upgraded to natively consume these tuples (it expects a YAML file). 
    // `WRITE_BUSCO_VERSION` safely converts the tuple back into a `versions.yml` file to prevent a 
    // `MissingMethodException` during MultiQC rendering. 
    // This `WRITE_BUSCO_VERSION` workaround should be REMOVED once the overarching `nf-core/funcscan` 
    // pipeline's template is synced/upgraded to handle `topic:` version tuples natively.
    WRITE_BUSCO_VERSION ( BUSCO_QC.out.versions_busco )
    ch_versions = ch_versions.mix(WRITE_BUSCO_VERSION.out.versions)
    
    ch_multiqc_files = ch_multiqc_files.mix(BUSCO_QC.out.short_summaries_json.map{ it[1] })

    // 2B. QUAST on Genomes
    QUAST ( ch_genomes, [[:], []], [[:], []] )

    // TODO: nf-core is migrating module version emissions to use Nextflow's new `topic: versions` system, 
    // which emits a tuple of `[process, component, version]` rather than a standard `versions.yml` file.
    // However, the `softwareVersionsToYAML` script used in this pipeline's template has not yet been 
    // upgraded to natively consume these tuples (it expects a YAML file). 
    // `WRITE_QUAST_VERSION` safely converts the tuple back into a `versions.yml` file to prevent a 
    // `MissingMethodException` during MultiQC rendering. 
    // This `WRITE_QUAST_VERSION` workaround should be REMOVED once the overarching `nf-core/funcscan` 
    // pipeline's template is synced/upgraded to handle `topic:` version tuples natively.
    WRITE_QUAST_VERSION ( QUAST.out.versions_quast )
    ch_versions = ch_versions.mix(WRITE_QUAST_VERSION.out.versions)
    ch_multiqc_files = ch_multiqc_files.mix(QUAST.out.results.map{ it[1] })

    // -----------------------------------------------------------------------
    // 3. FILTERING LOGIC
    // -----------------------------------------------------------------------
    GET_BUSCO_SCORE ( BUSCO_QC.out.short_summaries_json )
    
    // Create BGC input channel: Prefer GBK if available, else FASTA
    // This allows plantiSMASH to use existing annotations (better) or predict genes (fallback)
    ch_bgc_input = samplesheet.map { meta, fasta, faa, gbk -> 
        def input_file = gbk ? gbk : fasta
        return [ meta, input_file ]
    }

    // Join genome/bgc_input with busco score
    // We join on meta.id. Note: join might drop if keys don't match, ensuring exact match.
    ch_filtering_input = ch_bgc_input.join(GET_BUSCO_SCORE.out.score)

    // Branch the data: 'pass' goes to mining, 'fail' stops here.
    ch_quality_filtered = ch_filtering_input
        .branch { meta, bgc_file, score ->
            pass: (score as float) >= (params.busco_threshold as float)
                return [ meta, bgc_file ]
            fail: true
                return [ meta, bgc_file ]
        }
 
    // -----------------------------------------------------------------------
    // 4. MINING (Parallel)
    // -----------------------------------------------------------------------

    // Preparing Database (Run once)
    PLANTISMASH_DATABASES ()
    ch_antismash_db = PLANTISMASH_DATABASES.out.db

    // A. BGC Mining with plantiSMASH (Only on passing genomes)
    PLANTISMASH ( ch_quality_filtered.pass, ch_antismash_db )
    ch_versions = ch_versions.mix(PLANTISMASH.out.versions)

    // B. AMP Mining
    // Use the cleaned proteomes corresponding to passing genomes
    ch_proteomes_filtered = ch_quality_filtered.pass
        .map { meta, genome -> meta }
        .join(ch_clean_proteomes)
    
    
    // Extract GBKs for AMP subworkflow
    ch_gbk_inputs = samplesheet
        .map { meta, fasta, faa, gbk -> 
            gbk ? [ meta, gbk ] : null
        }
    
    GUNZIP ( ch_gbk_inputs )
    ch_versions = ch_versions.mix(GUNZIP.out.versions)
    ch_gbks_for_amp = GUNZIP.out.gunzip

    if (params.run_amp_screening) {
        AMP (
            ch_quality_filtered.pass,
            ch_proteomes_filtered,
            Channel.empty(),
            ch_gbks_for_amp,
            Channel.empty()
        )
        ch_versions = ch_versions.mix(AMP.out.versions)
    }

    // -----------------------------------------------------------------------
    // 5. AGGREGATION & CLUSTERING (BiG-SCAPE)
    // -----------------------------------------------------------------------

    if (params.run_bigscape) {
        // Collect all plantiSMASH output directories
        ch_plantismash_dirs = PLANTISMASH.out.results.map { meta, dir -> dir }.collect()

        // Flatten into a single directory of GBKs
        COLLECT_GENBANKS ( ch_plantismash_dirs )

        // Extract Pfam DB path from downloaded databases
        // Note: We use the *directory* output from PLANTISMASH_DATABASES, which contains the full DB structure
        ch_pfam_db = PLANTISMASH_DATABASES.out.db.map { db_dir -> file("${db_dir}/generic_modules/fullhmmer/Pfam-A.hmm") }

        // Run BiG-SCAPE
        BIGSCAPE ( COLLECT_GENBANKS.out.bgc_dir, ch_pfam_db )
        ch_versions = ch_versions.mix(BIGSCAPE.out.versions)
    }

    // -----------------------------------------------------------------------
    // 6. MULTIQC & SOFTWARE VERSIONS
    // -----------------------------------------------------------------------

    // Collate and save software versions
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_' + 'funcscan_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )
        .set { ch_collated_versions }

    ch_multiqc_config = Channel.fromPath(
        "${projectDir}/assets/multiqc_config.yml",
        checkIfExists: true
    )
    ch_multiqc_custom_config = params.multiqc_config
        ? Channel.fromPath(params.multiqc_config, checkIfExists: true)
        : Channel.empty()
    ch_multiqc_logo = params.multiqc_logo
        ? Channel.fromPath(params.multiqc_logo, checkIfExists: true)
        : Channel.fromPath("${workflow.projectDir}/docs/images/nf-core-funcscan_logo_light.png", checkIfExists: true)

    summary_params = paramsSummaryMap(
        workflow,
        parameters_schema: "nextflow_schema.json"
    )
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml')
    )
    ch_multiqc_custom_methods_description = params.multiqc_methods_description
        ? file(params.multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description)
    )

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true,
        )
    )

    MULTIQC(
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        [],
    )
    
    emit:
    versions       = ch_versions
    multiqc_report = MULTIQC.out.report.toList()
}