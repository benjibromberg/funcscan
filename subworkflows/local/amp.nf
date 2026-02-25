/*
    Run AMP screening tools
*/

include { MACREL_CONTIGS                                              } from '../../modules/nf-core/macrel/contigs/main'
include { HMMER_HMMSEARCH as AMP_HMMER_HMMSEARCH                      } from '../../modules/nf-core/hmmer/hmmsearch/main'
include { AMPLIFY_PREDICT                                             } from '../../modules/nf-core/amplify/predict/main'
include { AMPIR                                                       } from '../../modules/nf-core/ampir/main'
include { AMP_DATABASE_DOWNLOAD                                       } from '../../modules/local/amp_database_download'
include { AMPCOMBI2_PARSETABLES                                       } from '../../modules/nf-core/ampcombi2/parsetables'
include { AMPCOMBI2_COMPLETE                                          } from '../../modules/nf-core/ampcombi2/complete'
include { AMPCOMBI2_CLUSTER                                           } from '../../modules/nf-core/ampcombi2/cluster'
include { AMPCOMBI_ENSURE_CONTIG                                      } from '../../modules/local/ampcombi_ensure_contig'
include { GUNZIP as GUNZIP_MACREL_PRED ; GUNZIP as GUNZIP_MACREL_ORFS } from '../../modules/nf-core/gunzip/main'
include { GUNZIP as AMP_GUNZIP_HMMER_HMMSEARCH                        } from '../../modules/nf-core/gunzip/main'
include { TABIX_BGZIP as AMP_TABIX_BGZIP                              } from '../../modules/nf-core/tabix/bgzip/main'
include { MERGE_TAXONOMY_AMPCOMBI                                     } from '../../modules/local/merge_taxonomy_ampcombi'
include { AMPCOMBI_SHINY_COMPAT                                       } from '../../modules/local/ampcombi_shiny_compat'

workflow AMP {
    take:
    fastas          // tuple val(meta), path(contigs)
    faas            // tuple val(meta), path(PROKKA/PRODIGAL.out.faa)
    tsvs            // tuple val(meta), path(MMSEQS_CREATETSV.out.tsv)
    gbks            // tuple val(meta), path(ANNOTATION_ANNOTATION_TOOL.out.gbk)
    tsvs_interpro   // tuple val(meta), path(INTERPROSCAN.out.tsv)'

    main:
    ch_versions                    = Channel.empty()
    ch_ampresults_for_ampcombi     = Channel.empty()
    ch_macrel_faa                  = Channel.empty()
    ch_ampcombi_summaries          = Channel.empty()
    ch_ampcombi_complete           = null

    // When adding new tool that requires FAA, make sure to update conditions
    // in funcscan.nf around annotation and AMP subworkflow execution
    // to ensure annotation is executed!
    ch_faa_for_amplify             = faas
    ch_faa_for_amp_hmmsearch       = faas
    ch_faa_for_ampir               = faas
    ch_faa_for_ampcombi            = faas
    ch_gbk_for_ampcombi            = gbks
    ch_interpro_for_ampcombi       = tsvs_interpro

    // AMPLIFY
    if ( !params.amp_skip_amplify ) {
        AMPLIFY_PREDICT ( ch_faa_for_amplify, [] )
        ch_versions                = ch_versions.mix( AMPLIFY_PREDICT.out.versions )
        ch_ampresults_for_ampcombi = ch_ampresults_for_ampcombi.mix( AMPLIFY_PREDICT.out.tsv )
    }

    // MACREL
    if ( !params.amp_skip_macrel ) {
        MACREL_CONTIGS ( fastas )
        ch_versions                = ch_versions.mix( MACREL_CONTIGS.out.versions )
        GUNZIP_MACREL_PRED ( MACREL_CONTIGS.out.amp_prediction )
        GUNZIP_MACREL_ORFS ( MACREL_CONTIGS.out.all_orfs )
        ch_versions                = ch_versions.mix( GUNZIP_MACREL_PRED.out.versions )
        ch_versions                = ch_versions.mix( GUNZIP_MACREL_ORFS.out.versions )
        ch_ampresults_for_ampcombi = ch_ampresults_for_ampcombi.mix( GUNZIP_MACREL_PRED.out.gunzip )
        ch_macrel_faa              = ch_macrel_faa.mix( GUNZIP_MACREL_ORFS.out.gunzip )
        ch_faa_for_ampcombi        = ch_faa_for_ampcombi.mix( ch_macrel_faa )
    }

    // AMPIR
    if ( !params.amp_skip_ampir ) {
        AMPIR ( ch_faa_for_ampir, params.amp_ampir_model, params.amp_ampir_minlength, 0.0 )
        ch_versions                = ch_versions.mix( AMPIR.out.versions )
        ch_ampresults_for_ampcombi = ch_ampresults_for_ampcombi.mix( AMPIR.out.amps_tsv )
    }

    // HMMSEARCH
    if ( params.amp_run_hmmsearch ) {
        if ( params.amp_hmmsearch_models ) { ch_amp_hmm_models = Channel.fromPath( params.amp_hmmsearch_models, checkIfExists: true ) } else { error('[nf-core/funcscan] error: HMM model files not found for --amp_hmmsearch_models! Please check input.') }

        ch_amp_hmm_models_meta = ch_amp_hmm_models
            .map {
                file ->
                    def meta   = [:]
                    meta['id'] = file.extension == 'gz' ? file.name - '.hmm.gz' :  file.name - '.hmm'
                [ meta, file ]
            }

        ch_in_for_amp_hmmsearch = ch_faa_for_amp_hmmsearch
                                    .combine( ch_amp_hmm_models_meta )
                                    .map {
                                        meta_faa, faa, meta_hmm, hmm ->
                                            def meta_new = [:]
                                            meta_new['id']     = meta_faa['id']
                                            meta_new['hmm_id'] = meta_hmm['id']
                                        [ meta_new, hmm, faa, params.amp_hmmsearch_savealignments, params.amp_hmmsearch_savetargets, params.amp_hmmsearch_savedomains ]
                                    }

        AMP_HMMER_HMMSEARCH ( ch_in_for_amp_hmmsearch )
        ch_versions = ch_versions.mix( AMP_HMMER_HMMSEARCH.out.versions )
        AMP_GUNZIP_HMMER_HMMSEARCH ( AMP_HMMER_HMMSEARCH.out.output )
        ch_versions = ch_versions.mix( AMP_GUNZIP_HMMER_HMMSEARCH.out.versions )
        ch_AMP_GUNZIP_HMMER_HMMSEARCH = AMP_GUNZIP_HMMER_HMMSEARCH.out.gunzip
            .map { meta, file ->
                [ [id: meta.id], file ]
            }
        ch_ampresults_for_ampcombi = ch_ampresults_for_ampcombi.mix( ch_AMP_GUNZIP_HMMER_HMMSEARCH )
    }

    // AMPCOMBI2
    ch_input_for_ampcombi = ch_ampresults_for_ampcombi
        .groupTuple()
        .join( ch_faa_for_ampcombi )
        .join( ch_gbk_for_ampcombi, remainder: true )
        .join( ch_interpro_for_ampcombi, remainder: true )
        .map { meta, amp, faa, gbk, interpro ->
            [ meta, amp, faa, gbk ?: [], interpro ?: [] ]
        }
        .multiMap{
            input: [ it[0], it[1] ]
            faa: it[2]
            gbk: it[3]
            interpro: it [4]
        }

    // AMPCOMBI2::PARSETABLES
    if ( params.amp_ampcombi_db != null ) {
        AMPCOMBI2_PARSETABLES ( ch_input_for_ampcombi.input,  ch_input_for_ampcombi.faa,  ch_input_for_ampcombi.gbk, params.amp_ampcombi_db_id, params.amp_ampcombi_db, ch_input_for_ampcombi.interpro )
    } else {
        AMP_DATABASE_DOWNLOAD( params.amp_ampcombi_db_id )
        ch_versions = ch_versions.mix( AMP_DATABASE_DOWNLOAD.out.versions )
        ch_ampcombi_input_db = AMP_DATABASE_DOWNLOAD.out.db
        AMPCOMBI2_PARSETABLES ( ch_input_for_ampcombi.input, ch_input_for_ampcombi.faa, ch_input_for_ampcombi.gbk, params.amp_ampcombi_db_id, ch_ampcombi_input_db, ch_input_for_ampcombi.interpro )
    }
    ch_versions = ch_versions.mix( AMPCOMBI2_PARSETABLES.out.versions )

    // [Plant Mode] Ensure contig_id is present even if GBK locus_tags don't match FASTA
    AMPCOMBI_ENSURE_CONTIG ( AMPCOMBI2_PARSETABLES.out.tsv )
    ch_versions = ch_versions.mix( AMPCOMBI_ENSURE_CONTIG.out.versions )

    ch_ampcombi_summaries = AMPCOMBI_ENSURE_CONTIG.out.tsv.map{ it[1] }.collect()

    // AMPCOMBI2::COMPLETE
    // Cannot evaluate channel size in a standard Groovy if() statement. Process dynamically.
    ch_summaries_branch = ch_ampcombi_summaries
        .branch {
            multiple: it.size() > 1
            single: true
        }

    AMPCOMBI2_COMPLETE(ch_summaries_branch.multiple)
    ch_versions = ch_versions.mix( AMPCOMBI2_COMPLETE.out.versions )
    ch_ampcombi_complete = AMPCOMBI2_COMPLETE.out.tsv
                            .mix(ch_summaries_branch.single.map{ it -> it[0] })
                            .filter { file -> file.countLines() > 1 }

    // AMPCOMBI2::CLUSTER
    // Only runs if ch_ampcombi_complete emitted an item (dynamically handled by Nextflow)
    AMPCOMBI2_CLUSTER ( ch_ampcombi_complete )
    ch_versions = ch_versions.mix( AMPCOMBI2_CLUSTER.out.versions )

    // AMPCOMBI_SHINY_COMPAT (Adds missing columns so the dashboard doesn't crash)
    AMPCOMBI_SHINY_COMPAT ( AMPCOMBI2_CLUSTER.out.cluster_tsv )
    ch_versions = ch_versions.mix( AMPCOMBI_SHINY_COMPAT.out.versions )

    // MERGE_TAXONOMY
    if ( params.run_taxa_classification ) {
        // Need to join the cluster TSV with the list of mmseqs TSVs
        // But since there might be one cluster file taking ALL mmseqs TSVs, we pass the TSV list entirely
        ch_mmseqs_taxonomy_list = tsvs.map{ it[1] }.collect()

        MERGE_TAXONOMY_AMPCOMBI( AMPCOMBI_SHINY_COMPAT.out.cluster_tsv, ch_mmseqs_taxonomy_list )
        ch_versions = ch_versions.mix( MERGE_TAXONOMY_AMPCOMBI.out.versions )

        ch_tabix_input = Channel.of( [ 'id':'ampcombi_complete_summary_taxonomy' ] )
            .combine( MERGE_TAXONOMY_AMPCOMBI.out.tsv )

        AMP_TABIX_BGZIP( ch_tabix_input )
        ch_versions = ch_versions.mix( AMP_TABIX_BGZIP.out.versions )
    }

    emit:
    versions = ch_versions
}
