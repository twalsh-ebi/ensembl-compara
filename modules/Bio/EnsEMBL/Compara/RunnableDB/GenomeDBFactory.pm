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

=cut


=pod 

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory

=head1 DESCRIPTION

This Runnable flows some GenomeDB ids, depending on a few parameters.
The source is one of (by decreasing priority):
 - a species set given by species_set_id
 - a method_link_species_set given by mlss_id
 - a species set given by name
 - a species set given by collection name
 - all current GenomeDBs
 - all the GenomeDBs

The set of GenomeDBs may be filtered further, whether by a positive filter
(parameter 'include_species') or a negative filter (parameter 'exclude_species').

The default is to flow all the GenomeDBs fetched by the previous rule, but
specific kinds of GenomeDBs can be controlled individually:
 - polyploid_genomes : principal GenomeDB of polyploid genomes
 - component_genomes : component GenomeDBs of polyploid genomes
 - normal_genomes : GenomeDBs not related to polyploid genomes
Those 3 parameters are set to 1 by default, but can be set to 0 to prevent
dataflowing some GenomeDBs.

IDs are flown on branch "fan_branch_code" (default: 2)

=cut


package Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils qw(destringify);
use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::EnsEMBL::Utils::Scalar qw(assert_integer);

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

sub param_defaults {
    return {
        # set to 0 to remove some genomes from the factory
        'polyploid_genomes' => 1,
        'component_genomes' => 1,
        'normal_genomes'    => 1,
        'ancestral_genomes' => 0,
        # list of genome db names to exclude
        'exclude_species' => [],

        # List of GenomeDB attribute names that will be added to the output_ids
        'extra_parameters'  => [],
        'genome_db_data_source' => undef,   # Alternative source for these attributes
        'fetch_methods'     => 0,

        'fan_branch_code'   => 2,
        
        # also flow an arrayref of all genome_db_ids to this branch
        'arrayref_branch'   => undef, 

        # Definition of the species-set
        'species_set_id'    => undef,
        'species_set_name'  => undef,
        'collection_name'   => undef,
        'mlss_id'           => undef,
        'all_current'       => undef,

        # Set to 1 to expand polyploid genomes and include any of
        # their components that have not already been included.
        'expand_polyploid_components' => 0,
    }
}

sub fetch_input {
    my $self = shift @_;

    # We try our best to get a list of GenomeDBs
    my $genome_dbs;

    if (my $species_set_id = $self->param('species_set_id')) {
        assert_integer($species_set_id, 'species_set_id');
        my $species_set    = $self->compara_dba()->get_SpeciesSetAdaptor->fetch_by_dbID($species_set_id) or $self->die_no_retry("Could not fetch ss with dbID=$species_set_id");
        $genome_dbs        = $species_set->genome_dbs();

    } elsif (my $mlss_id = $self->param('mlss_id')) {
        assert_integer($mlss_id, 'mlss_id');
        my $mlss    = $self->compara_dba->get_MethodLinkSpeciesSetAdaptor->fetch_by_dbID($mlss_id) or $self->die_no_retry("Could not fetch mlss with dbID=$mlss_id");
        $genome_dbs = $mlss->species_set->genome_dbs;

    } elsif (my $species_set_name = $self->param('species_set_name')) {
        my $species_sets   = $self->compara_dba()->get_SpeciesSetAdaptor->fetch_all_by_name($species_set_name);
        die "Could not fetch ss with name=$species_set_name" unless scalar(@$species_sets);
        die "Too many ss with name=$species_set_name" if scalar(@$species_sets) > 1;
        $genome_dbs        = $species_sets->[0]->genome_dbs();

    } elsif (my $collection_name = $self->param('collection_name')) {
        my $species_set    = $self->compara_dba()->get_SpeciesSetAdaptor->fetch_collection_by_name($collection_name) or $self->die_no_retry("Could not fetch collection ss with name=$collection_name");
        $genome_dbs        = $species_set->genome_dbs();

    } elsif ($self->param('all_current')) {
        $genome_dbs = $self->compara_dba->get_GenomeDBAdaptor->fetch_all_current();

    } elsif ($self->param('all_in_current_gene_trees')) {
        my %id_to_gdb;
        my $mlss_adaptor = $self->compara_dba->get_MethodLinkSpeciesSetAdaptor();
        foreach my $method_type ('PROTEIN_TREES', 'NC_TREES') {
            foreach my $mlss (@{$mlss_adaptor->fetch_all_by_method_link_type($method_type)}) {
                next unless $mlss->is_current;
                foreach my $genome_db (@{$mlss->species_set->genome_dbs}) {
                    next unless $genome_db->is_current;
                    $id_to_gdb{$genome_db->dbID} = $genome_db;
                }
            }
        }
        $genome_dbs = [values %id_to_gdb];

    } else {
        $genome_dbs = $self->compara_dba->get_GenomeDBAdaptor->fetch_all();
    }

    if ($self->param_is_defined('include_species')) {
        my @species_to_include = @{destringify($self->param('include_species'))};
        throw("'include_species' array is empty") if scalar(@species_to_include) == 0;

        my %genome_dbs_by_name;
        foreach my $gdb (@{$genome_dbs}) {
            push(@{$genome_dbs_by_name{$gdb->name}}, $gdb);
        }

        my @included_gdbs;
        foreach my $species_name (@species_to_include) {
            if (exists $genome_dbs_by_name{$species_name}) {
                push(@included_gdbs, @{$genome_dbs_by_name{$species_name}});
            } else {
                throw("'include_species' array element '$species_name' not found in available genome_dbs");
            }
        }
        $genome_dbs = \@included_gdbs;
    }

    if ($self->param('expand_polyploid_components')) {
        foreach my $gdb (@{$genome_dbs}){
            if ($gdb->is_polyploid()) {
                foreach my $comp_gdb (@{$gdb->component_genome_dbs()}) {
                    if (!grep { $comp_gdb->dbID == $_->dbID } @{$genome_dbs}) {
                        push(@{$genome_dbs}, $comp_gdb);
                    }
                }
            }
        }
    }

    # Now we apply the filters
    # Note that to filter out some GenomeDBs, we keep the other ones !
    $genome_dbs = [grep {$_->name ne 'ancestral_sequences'} @$genome_dbs] if not $self->param('ancestral_genomes');
    $genome_dbs = [grep {not $_->is_polyploid} @$genome_dbs] if not $self->param('polyploid_genomes');
    $genome_dbs = [grep {not $_->genome_component} @$genome_dbs] if not $self->param('component_genomes');
    $genome_dbs = [grep {($_->name eq 'ancestral_sequences') or $_->is_polyploid or $_->genome_component} @$genome_dbs] if not $self->param('normal_genomes');


    # filter out exclude_species
    my %exclude_species_map;
    my $excluded_species = $self->param('exclude_species');
    if ( ref $excluded_species eq 'ARRAY' ) {
        @exclude_species_map{ @$excluded_species } = ();
    } else {
        @exclude_species_map{ split(/,/, $excluded_species) } = ();
    }
    my @gdbs = ();
    foreach my $gdb ( @{ $genome_dbs } ){
        push(@gdbs, $gdb) unless exists $exclude_species_map{$gdb->name};
    }
    $genome_dbs = \@gdbs;

    if ($self->param('genome_db_data_source')) {
        my $genomedb_dba = $self->get_cached_compara_dba('genome_db_data_source');
        my $genomedb_adaptor = $genomedb_dba->get_GenomeDBAdaptor;
        $genome_dbs = [map {$genomedb_adaptor->fetch_by_dbID($_->dbID)} @$genome_dbs];
    }

    my %extra_data = map {$_->dbID => {}} @$genome_dbs;
    $self->param('extra_data', \%extra_data);

    foreach my $genome_db (@$genome_dbs) {
        my $mlsss = $self->compara_dba->get_MethodLinkSpeciesSetAdaptor->fetch_all_by_GenomeDB($genome_db);
        my %method_hash;
        foreach my $mlss (@$mlsss) {
            $method_hash{$mlss->method->type}++ if $mlss->is_current;
        }
        $extra_data{$genome_db->dbID}->{'methods'} = \%method_hash;
    }

    $self->param('genome_dbs', $genome_dbs);
}


sub write_output {
    my $self = shift;
    
    my $extra_data = $self->param('extra_data');
    foreach my $gdb (@{$self->param('genome_dbs')}) {
        my $h = { 'genome_db_id' => $gdb->dbID };
        my $d = $extra_data->{$gdb->dbID};
        foreach my $p (@{$self->param('extra_parameters')}) {
            if ($gdb->can($p)) {
                $h->{$p} = $gdb->$p;
            } else {
                $h->{$p} = $d->{$p};
            }
        }
        $self->dataflow_output_id($h, $self->param('fan_branch_code'));
    }

    # Dataflow the GenomeDBs
    if ( $self->param('arrayref_branch') ) {
        my @genome_db_id_list;
        foreach my $gdb ( @{$self->param('genome_dbs')} ) {
            push( @genome_db_id_list, $gdb->dbID );
        }
        $self->dataflow_output_id({ 'genome_db_ids' => \@genome_db_id_list }, $self->param('arrayref_branch')); # to cdhit
    }
    
}

1;
