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

Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::StoreMemberBiotypeGroupTag

=cut

package Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::StoreMemberBiotypeGroupTag;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');


sub run {
    my $self = shift;

    my $mlss_id = $self->param_required('mlss_id');
    my $mlss = $self->compara_dba->get_MethodLinkSpeciesSetAdaptor->fetch_by_dbID($mlss_id);
    my $biotype_groups = $mlss->_get_gene_tree_member_biotype_groups();
    $mlss->store_tag('member_biotype_groups', join(',', @{$biotype_groups}));
}


1;
