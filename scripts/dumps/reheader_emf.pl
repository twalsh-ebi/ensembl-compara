#!/usr/bin/env perl
# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

=head1 NAME

reheader_emf.pl

=head1 DESCRIPTION

This script replaces the header in an EMF file.

=head1 OPTIONS

=over

=item B<[--help]>

Prints help message and exits.

=item B<[--emf_file PATH]>

EMF file to reheader.

=item B<[--reg_conf PATH]>

Ensembl registry file configuring Compara database.

=item B<[--rel_db STR]>

Compara database registry alias.

=item B<[--extension STR]>

EMF file extension.

=item B<[--clusterset_id STR]>

Gene-tree collection clusterset ID (e.g. 'default').

=item B<[--member_type STR]>

Member type (e.g. 'protein').

=back

=cut

use strict;
use warnings;

use File::Copy qw(move);
use File::Temp qw(tempfile);
use Getopt::Long;
use Pod::Usage;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::IO qw(iterate_lines work_with_file);
use Bio::EnsEMBL::Utils::Exception qw(throw);


my $help;
my $emf_file;
my $reg_conf;
my $rel_db;
my $extension;
my $clusterset_id;
my $member_type;

GetOptions(
    'help|?' => \$help,
    'emf_file=s' => \$emf_file,
    'reg_conf=s' => \$reg_conf,
    'rel_db=s' => \$rel_db,
    'extension=s' => \$extension,
    'clusterset_id=s' => \$clusterset_id,
    'member_type=s' => \$member_type,
);
pod2usage(-exitvalue => 0, -verbose => 1) if $help;
pod2usage(-verbose => 1) if !($emf_file && $reg_conf && $rel_db && $extension && $clusterset_id && $member_type);

Bio::EnsEMBL::Registry->load_all($reg_conf, 0, 0, 0, 'throw_if_missing');

my $compara_dba = Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->go_figure_compara_dba($rel_db);

my $sql = q/
    SELECT DISTINCT method_link_species_set_id
    FROM gene_tree_root
    WHERE clusterset_id = ?
    AND member_type = ?
/;

my $helper = $compara_dba->dbc->sql_helper;

my $mlss_id = $helper->execute_single_result($sql, undef, undef, [$clusterset_id, $member_type]);
my $mlss_dba = $compara_dba->get_MethodLinkSpeciesSetAdaptor();
my $mlss = $mlss_dba->fetch_by_dbID($mlss_id);

my $format;
if ($extension) {
    if ($extension =~ /(?<format>[a-z]+)\.emf$/) {
        $format = $+{'format'};
    } else {
        throw("unknown EMF file extension: '${extension}'");
    }
} else {
    throw("no EMF file extension specified");
}


my $date = scalar(localtime());
my $release = $compara_dba->get_MetaContainer->get_schema_version();
my $division = $compara_dba->get_division();
my $method_type = $mlss->method->type;
my $mlss_name = $mlss->name;

my @header_lines = (
    sprintf("##FORMAT (%s)", $format),
    sprintf("##DATE %s", $date),
    sprintf("##RELEASE %s", $release),
    sprintf("# clusterset_id: %s", $clusterset_id),
    sprintf("# comparative_dataset_name: %s", $mlss_name),
    sprintf("# comparative_method_type: %s", $method_type),
    sprintf("# division: %s", $division),
    sprintf("# member_type: %s", $member_type),
);

my $header = join("\n", @header_lines) . "\n\n";


my ($fh, $tmp_file) = tempfile(UNLINK => 1);
close($fh);

work_with_file($tmp_file, 'w', sub {
    my ($output_handle) = @_;

    print $output_handle $header;

    my $line_count = 0;
    my $reading_header = 0;
    work_with_file($emf_file, 'r', sub {
        my ($input_handle) = @_;

        iterate_lines($input_handle, sub {
            my ($line) = @_;

            if ($line_count == 0 && substr($line, 0, 1) eq '#') {
                $reading_header = 1;
            }

            if (!$reading_header) {
                print $output_handle $line;
            }

            if ($reading_header && substr($line, 0, 1) ne '#') {
                $reading_header = 0;
            }

            $line_count += 1;
        });
    });
});

move($tmp_file, $emf_file);
