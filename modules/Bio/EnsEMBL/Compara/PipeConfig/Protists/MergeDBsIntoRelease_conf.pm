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

Bio::EnsEMBL::Compara::PipeConfig::Protists::MergeDBsIntoRelease_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::Protists::MergeDBsIntoRelease_conf \
    -host mysql-ens-compara-prod-X -port XXXX

=head1 DESCRIPTION

A Protists specific pipeline to merge some production databases onto the release one.

The default parameters work well in the context of a Compara release for Protists (with a well-configured
Registry file). If the list of source-databases is different, have a look at the bottom of the base file
for alternative configurations.

Selected funnel analyses are blocked on pipeline initialisation.
These should be unblocked as needed during pipeline execution.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::Protists::MergeDBsIntoRelease_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::PipeConfig::MergeDBsIntoRelease_conf');


sub default_options {
    my ($self) = @_;

    return {
        %{$self->SUPER::default_options},

        'division' => 'protists',

        # All the source databases
        'src_db_aliases' => {
            'master_db'     => 'compara_master',
            'protein_db'    => 'compara_ptrees',
        },

        # From these databases, only copy these tables
        'only_tables' => {
            # Cannot be copied by populate_new_database because it does not contain the new
            # mapping_session_ids yet
            'master_db' => [ qw(mapping_session) ],
        },

        # These tables have a unique source. Content from other databases is ignored.
        'exclusive_tables' => {
            'mapping_session'         => 'master_db',
        },
    };
}

sub tweak_analyses {
    my $self = shift;
    $self->SUPER::tweak_analyses(@_);
    my $analyses_by_name = shift;

    # Block unguarded funnel analyses; to be unblocked as needed during pipeline execution.
    my @unguarded_funnel_analyses = (
        'fire_post_merge_processing',
        'enable_keys',
    );

    foreach my $logic_name (@unguarded_funnel_analyses) {
        $analyses_by_name->{$logic_name}->{'-analysis_capacity'} = 0;
    }

}


1;
