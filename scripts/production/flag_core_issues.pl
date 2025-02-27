#!/usr/bin/env perl
# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

=head1 NAME

flag_core_issues.pl

=head1 DESCRIPTION

This script performs rudimentary checks on the set of cores loaded by the
Compara registry for the given division, and flags potential issues.

=head1 SYNOPSIS

    perl flag_core_issues.pl --division ${COMPARA_DIV} --release ${CURR_ENSEMBL_RELEASE}

=head1 OPTIONS

=over

=item B<[--help]>

Prints help message and exits.

=item B<[--release CURR_ENSEMBL_RELEASE]>

(Optional) Ensembl release. If not specified, this is set from the environment variable ${CURR_ENSEMBL_RELEASE}.

=item B<[--division COMPARA_DIV]>

(Optional) Ensembl division. If not specified, this is set from the environment variable ${COMPARA_DIV}.

=back

=cut


use strict;
use warnings;

use File::Spec::Functions;
use File::Temp qw(tempfile);
use Getopt::Long;
use JSON qw(decode_json);
use Pod::Usage;
use Test::More;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::EnsEMBL::Utils::IO qw(slurp);
use Bio::EnsEMBL::Compara::Utils::RunCommand;
use Bio::EnsEMBL::Compara::Utils::Test qw(read_sqls);


sub get_core_schema_table_names {
    my ($release) = @_;

    my ($fh, $core_schema_file) = tempfile(UNLINK => 1);
    my $url = "https://raw.githubusercontent.com/Ensembl/ensembl/release/${release}/sql/table.sql";
    my $cmd = ['wget', $url, '--quiet', '--output-document', $core_schema_file];
    Bio::EnsEMBL::Compara::Utils::RunCommand->new_and_exec($cmd, { die_on_failure => 1 });
    my $core_schema_statements = Bio::EnsEMBL::Compara::Utils::Test::read_sqls($core_schema_file);
    close($fh);

    my @exp_core_table_names;
    foreach my $entry (@{$core_schema_statements}) {
        my ($title, $sql) = @{$entry};
        if ($title =~ /^CREATE TABLE (?:IF NOT EXISTS )?(`)?(?<table_name>.+)(?(1)\g1|)$/) {
            push(@exp_core_table_names, $+{table_name});
        }
    }

    return \@exp_core_table_names;
}


my $help;
my $division = $ENV{'COMPARA_DIV'};
my $release  = $ENV{'CURR_ENSEMBL_RELEASE'};
my $verbose = 0;

GetOptions(
    'help|?'     => \$help,
    'division=s' => \$division,
    'release=i'  => \$release,
    'verbose'    => \$verbose,
);
pod2usage(-exitvalue => 0, -verbose => 1) if $help;
pod2usage(-verbose => 1) if !$division or !$release;


Test::More->builder->output('/dev/null') unless ($verbose);

my %known_overlap_species = (
    'caenorhabditis_elegans' => 1,
    'drosophila_melanogaster' => 1,
    'saccharomyces_cerevisiae' => 1,
);

my $config_dir = catfile($ENV{'ENSEMBL_ROOT_DIR'}, 'ensembl-compara', 'conf', $division);
my $allowed_species_file = catfile($config_dir, 'allowed_species.json');
my $additional_species_file = catfile($config_dir, 'additional_species.json');
my $reg_conf = catfile($config_dir, 'production_reg_conf.pl');

my $registry = 'Bio::EnsEMBL::Registry';
$registry->load_all($reg_conf, 0, 0, 0, 'throw_if_missing');

my $ncbi_taxa_dba = $registry->get_DBAdaptor('ncbi_taxonomy', 'taxonomy');
my $ncbi_taxa_node_dba = $ncbi_taxa_dba->get_TaxonomyNodeAdaptor();


my %species_names_by_division;

if (-e $allowed_species_file) {
    $species_names_by_division{$division} = decode_json(slurp($allowed_species_file));
}

if (-e $additional_species_file) {
    my %additional_species = %{decode_json(slurp($additional_species_file))};
    while (my ($division, $division_species_names) = each %additional_species) {
        $species_names_by_division{$division} = $division_species_names;
    }
}


my @exp_core_table_names = sort @{get_core_schema_table_names($release)};
my %known_core_table_names = map { $_ => 1 } @exp_core_table_names;

my @divisions = sort keys %species_names_by_division;
my @registry_names = @{$registry->get_all_species()};

foreach my $division (@divisions) {
    my @species_names = sort @{$species_names_by_division{$division}};
    my %exp_overlap_species;
    my %info_by_species;
    my %info_by_db;

    my %div_host_to_db_names;
    my %species_by_assembly_dyad;
    foreach my $species_name (@species_names) {

        if (exists $known_overlap_species{$species_name}) {
            $exp_overlap_species{$species_name} = 1;
        }

        my @matching_registry_names = grep { $_ =~ /^\Q$species_name\E([1-9][0-9]*)?$/ } @registry_names;
        foreach my $registry_name (@matching_registry_names) {

            my $meta_container = $registry->get_adaptor($registry_name, 'Core', 'MetaContainer');
            my $meta_prod_name = $meta_container->get_production_name();

            if ($meta_prod_name ne $species_name) {
                next;
            }

            my $meta_division = $meta_container->get_division();
            if ($meta_division =~ /^Ensembl(?<division_name>.+)$/) {
                $meta_division = lc $+{division_name};
            } else {
                throw("unrecognised core meta division name: '$meta_division'");
            }
            my $meta_release = $meta_container->get_schema_version();

            my $meta_species_taxon_id = $meta_container->single_value_by_key('species.species_taxonomy_id');
            my $meta_taxon_id = $meta_container->get_taxonomy_id();

            my $db_conn = $registry->get_DBAdaptor($registry_name, 'core', 1)->dbc;
            my $db_name = $db_conn->dbname;

            $div_host_to_db_names{$db_conn->host}{$db_name} += 1;

            if (!exists $info_by_db{$db_name}) {
                my @db_table_names = sort @{$db_conn->db_handle->selectcol_arrayref('SHOW TABLES')};
                $info_by_db{$db_name} = {
                    'release' => $meta_release,
                    'table_names' => \@db_table_names,
                }
            }

            $info_by_species{$species_name}{$registry_name} = {
                'production_name' => $meta_prod_name,
                'division' => $meta_division,
                'database_name' => $db_name,
                'taxonomy_id' => $meta_taxon_id,
                'species_taxonomy_id' => $meta_species_taxon_id,
            };

            my $meta_assembly_accession = $meta_container->single_value_by_key('assembly.accession') // '';
            my $meta_assembly_default = $meta_container->single_value_by_key('assembly.default');
            my $assembly_dyad = $meta_assembly_accession . ':' . $meta_assembly_default;
            $species_by_assembly_dyad{$assembly_dyad}{$species_name} += 1;
        }
    }


    SKIP: {
        skip "no overlap cores expected in $division" if scalar(keys %exp_overlap_species) == 0;

        subtest "Overlap core resolution ($division)", sub {

            while (my ($species_name, $info_by_reg_entry) = each %info_by_species) {
                if (exists $exp_overlap_species{$species_name}) {

                    my $overlap_core_resolved = 0;
                    if (exists $info_by_reg_entry->{$species_name}) {
                        my $reg_entry_info = $info_by_reg_entry->{$species_name};
                        my $db_name = $reg_entry_info->{'database_name'};
                        my $db_info = $info_by_db{$db_name};

                        if ($reg_entry_info->{'production_name'} eq $species_name
                                && $reg_entry_info->{'division'} eq $division
                                && $db_info->{'release'} == $release) {
                            $overlap_core_resolved = 1;
                        }
                    }

                    ok($overlap_core_resolved, "$species_name overlap core resolution");

                    if ($overlap_core_resolved) {
                        my @other_registry_names = grep { $_ ne $species_name } keys %{$info_by_reg_entry};
                        foreach my $registry_name (@other_registry_names) {
                            my $reg_entry_info = $info_by_reg_entry->{$registry_name};
                            my $db_name = $reg_entry_info->{'database_name'};
                            delete $info_by_db{$db_name};
                            delete $info_by_reg_entry->{$registry_name};
                        }
                    }
                }
            }

            done_testing();
        };
    };

    subtest "Check core database metadata ($division)", sub {

        my @db_names = sort keys %info_by_db;
        foreach my $db_name (@db_names) {
            my $db_info = $info_by_db{$db_name};
            is($db_info->{'release'}, $release, "$db_name release");
            my @obs_core_table_names = grep { exists $known_core_table_names{$_} } @{$db_info->{'table_names'}};
            is_deeply(\@obs_core_table_names, \@exp_core_table_names, "$db_name tables");
        }

        done_testing();
    };

    subtest "Check core species metadata ($division)", sub {

        my @species_names = sort keys %info_by_species;
        foreach my $species_name (@species_names) {
            my $info_by_reg_entry = $info_by_species{$species_name};
            my @registry_names = sort keys %{$info_by_reg_entry};
            foreach my $registry_name (@registry_names) {
                my $reg_entry_info = $info_by_reg_entry->{$registry_name};
                my $db_name = $reg_entry_info->{'database_name'};
                is($reg_entry_info->{'production_name'}, $registry_name, "production name matches registry name '$registry_name' ($db_name)");
                is($reg_entry_info->{'production_name'}, $species_name, "production name matches species name for $registry_name");
                is($reg_entry_info->{'division'}, $division, "division matches for $registry_name");
            }
        }

        done_testing();
    };

    subtest "Check core species taxonomy metadata ($division)", sub {

        my @species_names = sort keys %info_by_species;
        foreach my $species_name (@species_names) {
            my $info_by_reg_entry = $info_by_species{$species_name};
            my @registry_names = sort keys %{$info_by_reg_entry};
            foreach my $registry_name (@registry_names) {
                my $reg_entry_info = $info_by_reg_entry->{$registry_name};
                my $db_name = $reg_entry_info->{'database_name'};

                my $taxon_node = $ncbi_taxa_node_dba->fetch_by_taxon_id($reg_entry_info->{'taxonomy_id'});
                ok(defined $taxon_node && $taxon_node->isa('Bio::EnsEMBL::Taxonomy::TaxonomyNode'),
                   "core meta entry 'species.taxonomy_id' is current for '$registry_name' ($db_name)")
                   || diag sprintf("species.taxonomy_id: %s", $reg_entry_info->{'taxonomy_id'});

                if (defined($reg_entry_info->{'species_taxonomy_id'})) {
                    my $species_taxon_node = $ncbi_taxa_node_dba->fetch_by_taxon_id($reg_entry_info->{'species_taxonomy_id'});
                    ok(defined $species_taxon_node && $species_taxon_node->isa('Bio::EnsEMBL::Taxonomy::TaxonomyNode'),
                       "core meta entry 'species.species_taxonomy_id' is current for $registry_name")
                       || diag sprintf("species.species_taxonomy_id: %s", $reg_entry_info->{'species_taxonomy_id'});
                }
            }
        }

        done_testing();
    };

    subtest "Check for duplicate/missing cores ($division)", sub {

        foreach my $species_name (@species_names) {

            my @species_registry_names;
            if (exists $info_by_species{$species_name}) {
                my $info_by_reg_entry = $info_by_species{$species_name};
                @species_registry_names = keys %{$info_by_reg_entry};
            }

            is(scalar(@species_registry_names), 1, "$species_name found in 1 core database");
        }

        done_testing();
    };

    subtest "Check for database name clashes ($division)", sub {

        my $core_db_pattern = qr/^(?<core_key>[a-z0-9_]+(?:_collection)?_core(?:_\d+)?_\d+)_\w+$/;

        my %div_cores_by_key;
        my %all_cores_by_key;
        while (my ($db_host, $db_names) = each %div_host_to_db_names) {
            foreach my $db_name (keys %{$db_names}) {
                if ($db_name =~ /$core_db_pattern/) {
                    push(@{$div_cores_by_key{$+{core_key}}}, $db_name);
                } else {
                    throw("failed to extract core key from database name: '$db_name'");
                }
            }

            my $cmd_args = [$db_host, '-e', "SHOW DATABASES"];
            my $cmd_opts = { die_on_failure => 1 };
            my $run_cmd = Bio::EnsEMBL::Compara::Utils::RunCommand->new_and_exec($cmd_args, $cmd_opts);
            foreach my $db_name (split(/\n/, $run_cmd->out)) {
                if ($db_name =~ /$core_db_pattern/) {
                    $all_cores_by_key{$+{core_key}}{$db_name} += 1;
                }
            }
        }

        foreach my $core_key (keys %div_cores_by_key) {
            my $db_name = $div_cores_by_key{$core_key}[0];
            my @clashing_db_names = grep { $_ ne $db_name } keys %{$all_cores_by_key{$core_key}};
            is(scalar(@clashing_db_names), 0, "$db_name has no database name clashes")
                || diag explain [sort @clashing_db_names];
        }

        done_testing();

    };

    subtest "Check for assembly dyad clashes ($division)", sub {

        foreach my $assembly_dyad (sort keys %species_by_assembly_dyad) {
            my ($assembly_accession, $assembly_default) = split(/:/, $assembly_dyad);
            my @dyad_species_names = sort keys %{$species_by_assembly_dyad{$assembly_dyad}};
            is(scalar(@dyad_species_names), 1, "assembly dyad ('$assembly_accession', '$assembly_default') found for one species")
                || diag explain [sort @dyad_species_names];
        }

        done_testing();
    }
}

done_testing();
