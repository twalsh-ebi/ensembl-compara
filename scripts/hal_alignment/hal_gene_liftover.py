#!/usr/bin/env python3

# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Do a liftover between two haplotypes in a HAL file.

Examples::
    # Do a liftover from GRCh38 to CHM13 of the human INS gene
    # along with 5 kb upstream and downstream flanking regions.
    python hal_gene_liftover.py --src-region chr11:2159779-2161221:-1 \
        --flank 5000 input.hal GRCh38 CHM13 output.psl

    # Do a liftover from GRCh38 to CHM13 of the
    # features specified in an input BED file.
    python hal_gene_liftover.py --src-bed-file input.bed \
        --flank 5000 input.hal GRCh38 CHM13 output.psl

"""

from argparse import ArgumentParser
import os
from pathlib import Path
import re
from subprocess import PIPE, Popen, run
from tempfile import TemporaryDirectory
from typing import Dict, Iterable, Mapping, NamedTuple, Union

#import pybedtools  # type: ignore


class SimpleRegion(NamedTuple):
    """A simple region."""
    chrom: str
    start: int
    end: int
    strand: str


def load_chr_sizes(hal_file: Union[Path, str], genome_name: str) -> Dict[str, int]:
    """Load chromosome sizes from an input HAL file.

    Args:
        hal_file: Input HAL file.
        genome_name: Name of the genome to get the chromosome sizes of.

    Returns:
        Dictionary mapping chromosome names to their lengths.

    """
    cmd = ['halStats', '--chromSizes', genome_name, hal_file]
    process = run(cmd, check=True, capture_output=True, text=True, encoding='ascii')

    chr_sizes = {}
    for line in process.stdout.splitlines():
        chr_name, chr_size = line.rstrip().split('\t')
        chr_sizes[chr_name] = int(chr_size)

    return chr_sizes


# pylint: disable-next=c-extension-no-member
def make_src_region_file(regions: Iterable[SimpleRegion],
                         chr_sizes: Mapping[str, int], bed_file: Union[Path, str],
                         flank_length: int = 0) -> None:
    """Make source region file.

    Args:
        regions: Regions to write to output file.
        chr_sizes: Mapping of chromosome names to their lengths.
        bed_file: Path of BED file to output.
        flank_length: Length of upstream/downstream flanking regions to request.

    Raises:
        ValueError: If any region has an unknown chromosome or invalid coordinates,
            or if `flank_length` is negative.

    """
    if flank_length < 0:
        raise ValueError(f"'flank_length' must be greater than or equal to 0: {flank_length}")

    with open(bed_file, 'w') as f:
        name = '.'
        score = 0  # halLiftover requires an integer score in BED input
        for region in regions:

            try:
                chr_size = chr_sizes[region.chrom]
            except KeyError as e:
                raise ValueError(f"chromosome ID not found in input file: '{region.chrom}'") from e

            if region.start < 0:
                raise ValueError(f'region start must be greater than or equal to 0: {region.start}')

            if region.end > chr_size:
                raise ValueError(f'region end ({region.end}) must not be greater than the'
                                 f' corresponding chromosome length ({region.chrom}: {chr_size})')

            flanked_start = max(0, region.start - flank_length)
            flanked_end = min(region.end + flank_length, chr_size)

            fields = [region.chrom, flanked_start, flanked_end, name, score, region.strand]
            print('\t'.join(str(x) for x in fields), file=f)


def parse_region(region: str) -> SimpleRegion:
    """Parse a region string.

    Args:
        region: Region string.

    Returns:
        A SimpleRegion object.

    Raises:
        ValueError: If `region` is an invalid region string.

    """
    seq_region_regex = re.compile(
        r'^(?P<chr>[^:]+):(?P<start>[0-9]+)-(?P<end>[0-9]+):(?P<strand>.+)$'
    )
    match = seq_region_regex.match(region)

    try:
        region_chr = match['chr']  # type: ignore
        match_start = int(match['start'])  # type: ignore
        region_end = int(match['end'])  # type: ignore
        match_strand = match['strand']  # type: ignore
    except TypeError as e:
        raise ValueError(f"region '{region}' could not be parsed") from e

    if match_start < 1:
        raise ValueError(f'region start must be greater than or equal to 1: {match_start}')
    region_start = match_start - 1

    if match_strand == '1':
        region_strand = '+'
    elif match_strand == '-1':
        region_strand = '-'
    else:
        raise ValueError(f"region '{region}' has invalid strand: '{match_strand}'")

    if region_start >= region_end:
        raise ValueError(f"region '{region}' has inverted/empty interval")

    return SimpleRegion(region_chr, region_start, region_end, region_strand)


if __name__ == '__main__':

    parser = ArgumentParser(description='Performs a gene liftover between two haplotypes in a HAL file.')
    parser.add_argument('hal_file', help="Input HAL file.")
    parser.add_argument('src_genome', help="Source genome name.")
    parser.add_argument('dest_genome', help="Destination genome name.")
    parser.add_argument('output_file', help="Output file.")

    parser.add_argument('--src-region', required=True, help="Region to liftover.")
    #group = parser.add_mutually_exclusive_group(required=True)
    #group.add_argument('--src-region', help="Region to liftover.")
    #group.add_argument('--src-bed-file', help="BED file containing regions to liftover.")

    parser.add_argument('--flank', default=0, type=int,
                        help="Requested length of upstream/downstream"
                             " flanking regions to include in query.")

    args = parser.parse_args()


    with TemporaryDirectory() as tmp_dir:

        query_bed_file = os.path.join(tmp_dir, 'src_regions.bed')

        src_regions = [parse_region(args.src_region)]
        #if args.src_region is not None:
        #    src_regions = [parse_region(args.src_region)]
        #else:  # i.e. bed_file is not None
        #    src_regions = pybedtools.BedTool(args.src_bed_file)

        src_chr_sizes = load_chr_sizes(args.hal_file, args.src_genome)

        make_src_region_file(src_regions, src_chr_sizes, query_bed_file, flank_length=args.flank)

        # halLiftover --outPSL in.hal GRCh38 in.bed CHM13 stdout | pslPosTarget stdin out.psl
        cmd1 = ['halLiftover', '--outPSL', args.hal_file, args.src_genome, query_bed_file,
                args.dest_genome, 'stdout']
        cmd2 = ['pslPosTarget', 'stdin', args.output_file]
        with Popen(cmd1, stdout=PIPE) as p1:
            with Popen(cmd2, stdin=p1.stdout) as p2:
                p2.wait()
                if p2.returncode != 0:
                    status_type = 'exit code' if p2.returncode > 0 else 'signal'
                    raise RuntimeError(
                        f'pslPosTarget terminated with {status_type} {abs(p2.returncode)}')
            p1.wait()
            if p1.returncode != 0:
                status_type = 'exit code' if p1.returncode > 0 else 'signal'
                raise RuntimeError(
                    f'halLiftover terminated with {status_type} {abs(p1.returncode)}')
