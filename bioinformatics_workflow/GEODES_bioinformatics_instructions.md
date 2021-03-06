---
title: "GEODES Instructions"
author: "Alex Linz"
date: "September 28, 2017"
output: html_document
---

##GEODES Quick Run:

On your submit node, submit files should be in "submits/", executables should be in "executables/", and scripts to run from the submit node in between steps in "scripts/". All necessary programs have already been installed and tarballed, and are in "zipped/".

The refence MAGs and SAGs from lakes_data drive are stored in your home folder in the submit node, as are any intermediate files less than 100MB. Total space on submit-4 is 1TB and no file limit. Files larger than 100MB but less than 1GB are stored on squid, and files larger than 1GB are stored on gluster. Intermediate files are occasionally zipped and moved from gluster to squid.

In gluster, initial RNA files are in "GEODES_metaT/" and metagenome assemblies and their information from lakes_data are in "metagenome_assemblies/".

```{bash, eval = F}
# Parts 1 and 2 do not depend on each other and can be run concurrently

# Part 1 - rRNA removal
./scripts/samplenames.sh
condor_submit submits/00split_fastq.sub
./scripts/path2splitfastqs.sh
condor_submit submits/01rRNA_removal.sub
./scripts/cat_RNA.sh
#Any time after this to get number of reads per metatranscriptome:
./scripts/MT_size.sh

# Part 2 - Nonredundant database building
./scripts/prephylodist.sh
condor_submit submits/02phylodist.sub
./scripts/postphylodist.sh
./scripts/refMAGs_SAGs_list.sh
condor_submit submits/03refMAGs_SAGs.sub
./scripts/algae_list.sh
condor_submit submits/04algae.sub
./scripts/split_metaG_gffs.sh
condor_submit submits/05.1metaG_gffs.sub
condor_submit submits/05.2metaG_gffs.sub
condor_submit submits/05.3metaG_gffs.sub
condor_submit submits/05.4metaG_gffs.sub
condor_submit submits/05.5metaG_gffs.sub
condor_submit submits/05.6metaG_gffs.sub
condor_submit submits/05.7metaG_gffs.sub
condor_submit submits/05.8metaG_gffs.sub
condor_submit submits/05.9metaG_gffs.sub
condor_submit submits/05.10metaG_gffs.sub
./scripts/move_CDS_output.sh
condor_submit submits/06cd-hit.sub #add fastaheaders back into this script
# Note: can start the mapping now
# calculate max size of clusters to include in 07nrdb_gff.sh with this command (add 1):
sort -nrk1,1 /mnt/gluster/amlinz/nonredundant_database.fna.clstr  | head -1 | cut -f1
./scripts/split_fastaheaders.sh
condor_submit submits/07nrdb_gff.sub
./scripts/cat_nrdbgff.sh
condor_submit submits/07.2nrdb.gff.sub

# Part 3 - mapping
# Note: must be run after Part 1. Can be started during Part 2 once you have the fasta file of the nonredundant database and before the gff file is finished processing.
condor_submit submits/08build_index.sub
ls /mnt/gluster/amlinz/GEODES_nonrRNA > path2mappingfastqs.txt
condor_submit submits/09mapping.sub

# Part 4 - mapped read counting (run after Part 3)
for file in /mnt/gluster/amlinz/GEODES_mapping_results/*; do sample=$(basename $file |cut -d'.' -f1); echo $sample;done > bamfiles.txt
condor_submit submits/10featurecounts.sub
# An optional manual curation - delete results files of samples with poor amplification of the standard (< 10 reads)
# This saves computational time down the road, and hopefully there are not many.
grep "pFN18A" *.CDS.txt | awk '{print $1,$7}'

./scripts/maketable.sh
condor_submit submits/11grep_genes.sub
./scripts/cat_geneinfo.sh

gzip *readcounts.txt
condor_submit submits/12genekey.sub

# Part 5 - binning metagenome assemblies - OPTIONAL
# Can be run at any point
# put metagenome names in metaG_samples.txt
condor_submit submits/13sample_metaGs.sub
# contigs.txt can be the same as metaG_samples.txt
condor_submit submits/14contig_filter.sub
condor_submit submits/15binning.sub
./scripts/move_bins.sh
ls metaG_bins > bins_to_classify.txt
condor_submit submits/16checkm.sub
./scripts/checkm_results.sh
condor_submit submits/17classify_phylodist.sub
cat *classonly.txt > phylodist_bin_classifications.txt

# Part 6 - mapping metagenomes - OPTIONAL
# Can be run after reference database in Part 3 and after metagenome sampling in Part 5
# modify 09mapping - 11grep_genes to reference sampled metagenomes instead of metatranscriptomes
# then run as above

# Part 7 - R processing
# These scripts can be sourced once paths are changed or run interactively. Make sure to NOT save large files in your github repo. Run one lake at a time to save RAM.
# Remove any remaining samples with poor standard amplification and normalize read counts to transcripts/L
transcripts_per_liter.R
# Process gene keys to include bin classifications
add_bin_classifications.R
# Calculate summary stats of the metagenomes and metatranscriptomes
summary_stats.R

```

