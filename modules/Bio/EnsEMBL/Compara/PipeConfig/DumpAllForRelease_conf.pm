=head1 LICENSE

See the NOTICE file distributed with this work for additional information
regarding copyright ownership.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::DumpAllForRelease_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpAllForRelease_conf -host mysql-ens-compara-prod-X -port XXXX \
         -division $COMPARA_DIV -dump_dir <path> -updated_mlss_ids <optional> -ancestral_db <optional> \
         -no_remove_existing_files <optional> -clean_intermediate_files <optional>

=head1 DESCRIPTION

The PipeConfig file for the pipeline that performs FTP dumps of everything required for a
given release. It will detect which pipelines have been run and dump anything new.

=cut


package Bio::EnsEMBL::Compara::PipeConfig::DumpAllForRelease_conf;

use strict;
use warnings;

use File::Basename qw(dirname);
use Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpTrees;
use Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpMultiAlign;
use Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpSpeciesTrees;
use Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpAncestralAlleles;
use Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpConstrainedElements;
use Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpConservationScores;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf; # for conditional dataflow and INPUT_PLUS

use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub default_options {
    my ($self) = @_;
    my $do = {
        %{$self->SUPER::default_options},

        ######################################################
        # Review these options prior to running each release #
        ######################################################

        # Where to put the new dumps and the symlinks
        'dump_root'    => $self->o('pipeline_dir'),
        'work_dir'     => $self->o('dump_root') . '/dump_hash/',

        # Dump registry options
        'reg_conf'            => $self->o('work_dir') . '/' . 'dump_reg_conf.pm',
        'compara_dump_host'   => undef,
        'ancestral_dump_host' => undef,
        'core_dump_hosts'     => undef,

        # Location of the previous dumps
        'ftp_root'     => '/nfs/production/flicek/ensembl/production/ensemblftp/',

        'prev_rel_ftp_root' => $self->o('ftp_root') . '/release-' . $self->o('prev_release'),

        'compara_db'   => 'compara_curr', # can be URL or reg alias
        'ancestral_db' => undef,

        'no_remove_existing_files' => undef, # on by default
        'clean_intermediate_files' => 0, # off by default

        # were there lastz patches this release? pass hive pipeline urls if yes, pass undef if no
        #  'lastz_patch_dbs' => [
        #  	'mysql://ensro@mysql-ens-compara-prod-3:4523/carlac_lastz_human_patches_92',
		#   'mysql://ensro@mysql-ens-compara-prod-3:4523/carlac_lastz_mouse_patches_92',
        #  ],
        'lastz_patch_dbs' => undef,

        ######################################################
        ######################################################


        # ----------------------------------------------------- #
        # the following options should remain largely unchanged #
        # ----------------------------------------------------- #
        # capacities for heavy-hitting jobs
        'dump_aln_capacity'   => 150,
		'dump_trees_capacity' => 10,
		'dump_ce_capacity'    => 10,
    	'dump_cs_capacity'    => 20,
        'dump_per_genome_cap' => 10,


    	# general settings
		'lastz_dump_path' => 'maf/ensembl-compara/pairwise_alignments', # where, from the FTP root, is the LASTZ dumps?
        'reuse_prev_rel'  => 1, # copy symlinks from previous release dumps
        #'updated_mlss_ids' => [1142,1143,1134,1141], #the list of mlss_ids that we have re_ran/updated and cannot be detected through first_release
        'updated_mlss_ids' => [],
		# define input options for DumpMultiAlign for each method_link_type
        'alignment_dump_options' => {
        	EPO              => {format => 'emf+maf'},
        	EPO_EXTENDED     => {format => 'emf+maf'},
        	PECAN            => {format => 'emf+maf'},
        	LASTZ_NET        => {format => 'maf', make_tar_archive => 1},
        },

        # define which params should ALWAYS be passed to each dump pipeline
        'default_dump_options' => {
        	DumpMultiAlign          => {
         		make_tar_archive => 0,
        	},
        	DumpConstrainedElements => {
        		compara_db => '#compara_db#',
        	},
        	DumpConservationScores  => {
        		compara_db => '#compara_db#',
        	},
        	DumpTrees               => {
        		rel_db               => '#compara_db#',
        		base_dir             => '#dump_root#',
        	},
        	DumpSpeciesTrees => {
        		compara_db  => '#compara_db#',
        		dump_dir    => '#dump_dir#/compara/species_trees',
        	},
        	DumpAncestralAlleles => {
        		compara_db => '#compara_db#',
        	},
        },

        # DumpMultiAlign options
        'split_size'          => 200,
        'masked_seq'          => 1,
        'method_link_types'   => 'BLASTZ_NET:TRANSLATED_BLAT:TRANSLATED_BLAT_NET:LASTZ_NET:PECAN:EPO:EPO_EXTENDED',
        'split_by_chromosome' => 1,
        'epo_reference_species' => [],

        # tree dump options
        'clusterset_id' => undef,
        'member_type'   => undef,
        'readme_dir'    => $self->check_dir_in_ensembl('ensembl-compara/docs/ftp'),    # where the template README files are
        'max_files_per_tar'     => 500,
        'batch_size'            => 25,    # how may trees' dumping jobs can be batched together

        # constrained elems & conservation scores
        'cs_readme'             => $self->check_file_in_ensembl('ensembl-compara/docs/ftp/conservation_scores.txt'),
        'ce_readme'             => $self->check_file_in_ensembl('ensembl-compara/docs/ftp/constrained_elements.txt'),
        'bigbed_autosql'        => $self->check_file_in_ensembl('ensembl-compara/scripts/pipeline/constrainedelements_autosql.as'),

        'uniprot_dir'  => '/nfs/ftp/public/databases/ensembl/ensembl_compara/gene_trees_for_uniprot/',
        'uniprot_file' => 'GeneTree_content.#clusterset_id#.e#curr_release#.txt',

    };
    return $do;
}

sub no_compara_schema {}    # Tell the base class not to create the Compara tables in the database

sub hive_meta_table {
    my ($self) = @_;
    return {
        %{$self->SUPER::hive_meta_table},       # here we inherit anything from the base class
        'hive_use_param_stack'  => 1,           # switch on the new param_stack mechanism
    }
}

sub pipeline_create_commands {
    my $self = shift;

    $self->{'_skip_reg_conf_file_check'} = 1;

    return [
        @{ $self->SUPER::pipeline_create_commands },

        $self->pipeline_create_commands_rm_mkdir(['dump_root', 'work_dir', 'dump_dir'], undef, $self->o('no_remove_existing_files')),
        $self->pipeline_create_commands_reg_conf_stub(),

        $self->db_cmd( 'CREATE TABLE other_gab (genomic_align_block_id bigint NOT NULL, PRIMARY KEY (genomic_align_block_id) )' ),
        $self->db_cmd( 'CREATE TABLE healthcheck (filename VARCHAR(400) NOT NULL, expected INT NOT NULL, dumped INT NOT NULL)' ),
    ];
}

sub pipeline_create_commands_reg_conf_stub {
    my ($self) = @_;

    my $reg_conf_file = $self->o('reg_conf');
    my $reg_conf_dir = dirname($reg_conf_file);

    my @cmd_args = (
        "mkdir -p $reg_conf_dir",
        "echo '1;' > $reg_conf_file",  # Even a registry stub must return a true value.
    );

    return @cmd_args;
}

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

        'dump_root'       => $self->o('dump_root' ),
        'dump_dir'        => $self->o('dump_dir'),
        'work_dir'        => $self->o('work_dir'),
        'ftp_root'        => $self->o('ftp_root'),
        'division'        => $self->o('division'),
        'genome_dumps_dir'=> $self->o('genome_dumps_dir'),
        'warehouse_dir'   => $self->o('warehouse_dir'),
        'uniprot_file'    => $self->o('uniprot_file'),
        'prev_rel_ftp_root' => $self->o('prev_rel_ftp_root'),

        # tree params
        'dump_trees_capacity' => $self->o('dump_trees_capacity'),
        'dump_per_genome_cap' => $self->o('dump_per_genome_cap'),
        'basename'            => '#member_type#_#clusterset_id#',
        'name_root'           => 'Compara.#curr_release#.#basename#',
        'hash_dir'            => '#work_dir#/#basename#',
        'target_dir'          => '#dump_dir#',
        'xml_dir'             => '#target_dir#/xml/ensembl-compara/homologies/',
        'emf_dir'             => '#target_dir#/emf/ensembl-compara/homologies/',
        'tsv_dir'             => '#target_dir#/tsv/ensembl-compara/homologies/',

        # ancestral alleles
        'anc_tmp_dir'    => "#work_dir#/ancestral_alleles",
        'anc_output_basedir' => 'fasta/ancestral_alleles',
        'anc_output_dir'     => "#dump_dir#/#anc_output_basedir#",
        'ancestral_dump_program' => $self->o('ancestral_dump_program'),
        'ancestral_stats_program' => $self->o('ancestral_stats_program'),

        # constrained elems & conservation scores
        'dump_cs_capacity'      => $self->o('dump_cs_capacity'),
        'dump_ce_capacity'      => $self->o('dump_ce_capacity'),
        'dump_features_exe'     => $self->o('dump_features_exe'),
        'cs_readme'             => $self->o('cs_readme'),
        'ce_readme'             => $self->o('ce_readme'),

        'export_dir'     => '#dump_dir#',
        'ce_output_dir'  => '#export_dir#/bed/ensembl-compara/#dirname#',
        'cs_output_dir'  => '#export_dir#/compara/conservation_scores/#dirname#',
        'hmm_library_basedir' => $self->o('hmm_library_basedir'),

        'bedgraph_file'  => '#work_dir#/#dirname#/gerp_conservation_scores.#name#.bedgraph',
        'chromsize_file' => '#work_dir#/#dirname#/gerp_conservation_scores.#name#.chromsize',
        'bigwig_file'    => '#cs_output_dir#/gerp_conservation_scores.#name#.#assembly#.bw',
        'bed_file'       => '#work_dir#/#dirname#/gerp_constrained_elements.#name#.bed',
        'bigbed_file'    => '#ce_output_dir#/gerp_constrained_elements.#name#.bb',

        # species trees
        'dump_species_tree_exe'  => $self->o('dump_species_tree_exe'),

        # dump alignments + aln patches
        'dump_aln_capacity'   => $self->o('dump_aln_capacity'),
        'split_size'          => $self->o('split_size'),
        'masked_seq'          => $self->o('masked_seq'),
        'dump_aln_program'    => $self->o('dump_aln_program'),
        'emf2maf_program'     => $self->o('emf2maf_program'),
        # 'make_tar_archive'    => '#make_tar_archive#',
        'split_by_chromosome' => $self->o('split_by_chromosome'),
        'output_dir'          => '#export_dir#/#format#/ensembl-compara/#aln_type#/#base_filename#',
        'output_file_gen'     => '#output_dir#/#base_filename#.#region_name#.#format#',
        'output_file'         => '#output_dir#/#base_filename#.#region_name##filename_suffix#.#format#',

        'compara_dump_host'   => $self->o('compara_dump_host'),
        'ancestral_dump_host' => $self->o('ancestral_dump_host'),
        'core_dump_hosts'     => $self->o('core_dump_hosts'),

        'clean_intermediate_files' => $self->o('clean_intermediate_files'),
    }
}


sub core_pipeline_analyses {
    my ($self) = @_;

    my @all_pa = (
        {   -logic_name => 'init_dump_registry',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FTPDumps::InitDumpRegistry',
            -input_ids  => [ {
                    'compara_db'           => $self->o('compara_db'),
                    'curr_release'         => $self->o('ensembl_release'),
                    'reuse_prev_rel'       => $self->o('reuse_prev_rel'),
                    'reg_conf'             => $self->o('reg_conf'),
                    'updated_mlss_ids'     => $self->o('updated_mlss_ids'),
                    'lastz_patch_dbs'      => $self->o('lastz_patch_dbs'),
                    'alignment_dump_options' => $self->o('alignment_dump_options'),
                    'default_dump_options' => $self->o('default_dump_options'),
                    'ancestral_db'         => $self->o('ancestral_db'),
                } ],
            -parameters => {
                'init_dump_registry_exe' => $self->o('init_dump_registry_exe'),
            },
            -flow_into  => [ 'create_all_dump_jobs' ],
            -rc_name    => '1Gb_job',
        },

        {   -logic_name => 'create_all_dump_jobs',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FTPDumps::CreateDumpJobs',
            -flow_into  => {
                '9->A' => [ 'DumpMultiAlign_start'          ],
                '2->A' => [ 'DumpTrees_start','add_hmm_lib' ],
                '3->A' => [ 'DumpConstrainedElements_start' ],
                '4->A' => [ 'DumpConservationScores_start'  ],
                '5->A' => [ 'DumpSpeciesTrees_start'        ],
                '6->A' => [ 'DumpAncestralAlleles_start'    ],
                '7->A' => [ 'DumpMultiAlignPatches_start'   ],
                '8->A' => [ 'create_ftp_skeleton'           ],
                'A->1' => [ 'final_funnel_check'            ],
            },
            -rc_name    => '1Gb_job',
        },

        #------------------------------------------------------------------#
        # create dummy analyses to make it clearer which pipeline is which #
        # and to pass any additional pipeline-specific parameters          #
        #------------------------------------------------------------------#
        {	-logic_name => 'DumpMultiAlign_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        	-flow_into  => [ 'DumpMultiAlign_MLSSJobFactory' ],
            -rc_name    => '1Gb_job',
        },
        {	-logic_name => 'DumpTrees_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        	-flow_into => [ 'dump_trees_pipeline_start' ],
            -rc_name    => '1Gb_job',
        },
        {	-logic_name => 'DumpConstrainedElements_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        	-flow_into  => [ 'mkdir_constrained_elems' ],
            -rc_name    => '1Gb_job',
        },
        {	-logic_name => 'DumpConservationScores_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        	-flow_into => [ 'mkdir_conservation_scores' ],
            -rc_name    => '1Gb_job',
        },
        {	-logic_name => 'DumpSpeciesTrees_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        	-flow_into  => ['mk_species_trees_dump_dir' ],
            -rc_name    => '1Gb_job',
        },
        {	-logic_name => 'DumpAncestralAlleles_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        	-flow_into  => [ 'mk_ancestral_dump_dir' ],
            -rc_name    => '1Gb_job',
        },
        {	-logic_name => 'DumpMultiAlignPatches_start',
        	-module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -rc_name    => '1Gb_job',
        	-flow_into  => {
        		'1->A' => [ 'DumpMultiAlign_MLSSJobFactory' ],
                        'A->1' => [ 'patch_lastz_funnel_check' ],
        	},
        },

       #------------------------------------------------------------------#


        {	-logic_name => 'create_ftp_skeleton',
        	-module     => 'Bio::EnsEMBL::Compara::RunnableDB::FTPDumps::FTPSkeleton',
            -rc_name    => '1Gb_job',
        	-flow_into => [ 'symlink_prev_dumps' ],
        },

        {	-logic_name => 'symlink_prev_dumps',
        	-module     => 'Bio::EnsEMBL::Compara::RunnableDB::FTPDumps::SymlinkPreviousDumps',
            -rc_name    => '1Gb_job',
                -flow_into => { 2 => 'create_all_dump_jobs' }, # to top up any missing dumps
        },

        {   -logic_name => 'patch_lastz_funnel_check',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FunnelCheck',
            -rc_name    => '1Gb_job',
            -flow_into  => [ { 'patch_lastz_dump' => INPUT_PLUS() } ],
        },

        {   -logic_name => 'patch_lastz_dump',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FTPDumps::PatchLastzDump',
            -rc_name    => '1Gb_job',
            -parameters => {
            	'lastz_dump_path' => $self->o('lastz_dump_path'),
            },
        },

        {   -logic_name => 'add_hmm_lib',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FTPDumps::AddHMMLib',
            -rc_name    => '1Gb_job',
            -parameters => {
                'ref_tar_path_templ' => '#warehouse_dir#/hmms/treefam/multi_division_hmm_lib.%s.tar.gz',
                'tar_ftp_path'       => '#dump_dir#/compara/multi_division_hmm_lib.tar.gz',
            },
        },

        {   -logic_name => 'final_funnel_check',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FunnelCheck',
            -rc_name    => '1Gb_job',
            -flow_into  => [ { 'final_registry_backup' => INPUT_PLUS() } ],
        },

        {   -logic_name => 'final_registry_backup',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::LogRegistry',
            -rc_name    => '1Gb_job',
            -flow_into  => [ { 'clean_files_decision' => { 'clean_intermediate_files' => $self->o('clean_intermediate_files') } } ],
        },

        {   -logic_name => 'clean_files_decision',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -rc_name    => '1Gb_job',
            -flow_into  => {
                1 => WHEN('#clean_intermediate_files#' => [ 'clean_dump_hash' ])
            },
        },

        {   -logic_name     => 'clean_dump_hash',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -rc_name        => '1Gb_24_hour_job',
            -parameters     => {
                'cmd' => 'rm -rf #work_dir#',
            },
            -flow_into =>  {
                1 => WHEN(
                    '#division# eq "vertebrates"' => 'move_uniprot_file',
                    ELSE 'remove_uniprot_file'
                ),
            },
        },

        {   -logic_name     => 'move_uniprot_file',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters     => {
                'uniprot_dir'   => $self->o('uniprot_dir'),
                'clusterset_id' => 'default',
                'cmd'           => join(' && ', (
                    'cd #dump_root#',
                    'rename vertebrates ensembl vertebrates.#uniprot_file#.gz',
                    'md5sum ensembl.#uniprot_file#.gz > ensembl.#uniprot_file#.gz.MD5SUM',
                    'mv ensembl.#uniprot_file#* #uniprot_dir#',
                ))
            },
            -rc_name       => '1Gb_datamover_job',
        },

        {   -logic_name     => 'remove_uniprot_file',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -rc_name        => '1Gb_job',
            -parameters     => {
                'clusterset_id' => 'default',
                'cmd'           => 'rm #dump_root#/#division#.#uniprot_file#.gz',
            },
        },


        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpMultiAlign::pipeline_analyses_dump_multi_align($self) },
        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpSpeciesTrees::pipeline_analyses_dump_species_trees($self) },
        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpAncestralAlleles::pipeline_analyses_dump_anc_alleles($self) },
        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpConstrainedElements::pipeline_analyses_dump_constrained_elems($self) },
        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpConservationScores::pipeline_analyses_dump_conservation_scores($self) },

    );

	# add DumpTree analyses seperately in order to set the collection_factory parameters
    my $tree_pa = Bio::EnsEMBL::Compara::PipeConfig::Parts::DumpTrees::pipeline_analyses_dump_trees($self);
    $tree_pa->[1]->{'-parameters'} = {
        'inputquery'    => 'SELECT clusterset_id, member_type FROM gene_tree_root WHERE tree_type = "tree" AND ref_root_id IS NULL GROUP BY clusterset_id, member_type',
        'db_conn'       => '#rel_db#',
    };
    push( @all_pa, @$tree_pa );
    return \@all_pa;
}

sub tweak_analyses {
    my $self = shift;
    my $analyses_by_name = shift;

    $analyses_by_name->{'dump_per_genome_homologies_tsv'}{'-parameters'}{'healthcheck_list'} = ['line_count', 'unexpected_nulls'];
}

1;
