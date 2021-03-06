---
title: "Full GEODES Workflow"
author: "Alex Linz"
date: "February 14, 2018"
output: html_document
---

This document contains detailed instructions on how to run the full GEODES analysis workflow, from quality-filtered metatranscriptomic file to a table of hits per gene. See the directories in analyses/ for lab notebooks and scripts.

Last updated 2018-02-14

#### A quick word on high-throughput computing

Because of the large amount of data from this project, I'm running my analyses in a high-throughput computing environment. I submit "jobs" (bits of analyses) from my "submit node" (computer where my home directory is located) and these jobs are sent off to open processors ("execute nodes") around campus. There are two files needed for this - ".sub" files state how many jobs to run, where to find the scripts, and what specs are needed. These are all stored in submits/ in my home folder. The executables, ".sh", are bash scripts that run the actual analysis, found in executables/. The more jobs I can split a task into, the more efficiently it will run - however, sometimes combining the results of many split jobs is prohibitively difficult. In some steps of this workflow, I've chosen to split each sample into many smaller files, while others I've submit one job per sample or even one job for all samples at once. This choice depends on the computational power required by each job and the ease of programming splitting and concatenation scripts.

UW-Madison Center for High-Throughput Computing (CHTC) runs on HTCondor, so all commands for submitting, checking, or removing jobs are from this program. If you want to run our workflow NOT in massive parallel, you can still use the bash (.sh) scripts. They accept one argument that is the input file name, path, or part of an input file name. So if you had one sample named "My_Favorite_Sample.fastq" you could run:

```{bash, eval = F}
./01rRNA_removal.sh /Path/To/My_Favorite_Sample.fastq
```

and receive files "My_Favorite_Sample_rRNA.fastq" and "My_Favorite_Sample_nonrRNA.fastq", as long as you had the program tarball sortmerna-2.1-linux-64.tar.gz in the same directory as 01rRNA_removal.sh. If you want to run several samples in sequence, you could use a for loop; if you have access to multiple threads, you could use a program to run a handful of samples in parallel on one computer.


#### A word on where all of our files are located:

- We run things through UW-Madison's Center for High Throughput Computing, specifically from submit-4.chtc.wisc.edu. I submit jobs and store short-term, small files on this submit node in /home/amlinz/
- The actual data files are way too large to be stored on the submit node. Instead, I have a gluster account where I keep the data files - from submit nodes, it is located at /mnt/gluster/amlinz. This means that instead of transferring data files with my executable in the submit node, I instead write a line in the executable that says "go to gluster and download this file." Therefore, I can only run these programs on computers with access to gluster. Also, please note that gluster is not for long-term storage, and it does not get backed up. Download any files you really want to keep.
- Some intermediate files are too big to transfer from the submit nodes and are referenced by many jobs at once, which can cause problems in Gluster. As long as these files are less than 1GB (zipped), I keep these on /squid/amlinz. The squid server can be referenced like a webpage in the submit scripts. This is great for tasks that have 1000s of jobs referencing 1-5 kind of big files.
- Backup copies of data and results are stored on the GEODES external hard drive. Final versions of results are stored in the McMahon Lab fileshare, lakes_data/.

All the code below is run from my submit node, and frequently references my large file system accounts. Keep this in mind if you are trying to replicate the workflow! Get your own accounts by contacting CHTC. Also, if you copied the .sh and .sub files directly from this github repo, you'll need to run "dos2unix" on them to get rid of my silly Windows line endings before running.

#### Installing programs in high throughput

How do you install programs on 9,999 computers at once? The program can't have any dependencies, and it can't go downloading something from the Internet every time I want to run a job. You'll need to build portable, easy-to-use files called installation tarballs. This is a .tar.gz file that contains all necessary files and dependencies to run a program. You send it in your submit file, and once at the execute node, unzip it, maybe update the PATH variable, and start running. This also means I can be sure that my jobs are using the same version of common programs like Python! To build one of these tarballs, you submit an interactive job to an execute node that is designated as a "build environment" and install the program in that directory. An example of how to do this for Python can be found here: http://chtc.cs.wisc.edu/python-jobs.shtml

As you can probably guess, building installation tarballs can get tricky. The tarballs used in this workflow are in /geodes/bioinformatics_workflow/programs - in theory, these should run on any Linux system, even if it's not a high-throughput execute node. I've also included instructions on how to install each of these programs as I use them in the workflow below. For one particularly hairy install, I coerced a labmate into building a Docker image for me. This is sort of like a virtual machine image, and it runs great provided you have Docker. If running this in CHTC, you can simply request nodes with Docker and run like normal. If you're running this on your own computer, it's up to you whether you want to install Docker or install CheckM. 

Happy Coding!

## Most recent workflow. 
####Use this if you want to replicate our protocol. Updated 2018-02-14

# rRNA removal

####Goal of this analysis

To remove ribosomal reads from the metatranscriptomes. We used an rRNA removal kit before sequencing, but 50-70% of the reads in the sample are still rRNA. We're not interested in these biased reads with little information about gene expression. Luckily the samples are big enough that 30-50% of reads is still plenty to look at non-rRNA expression.

####Approach

Starting with the quality filtered fastq files provided by the JGI through the Genome Portal, I will use Sortmerna to separate rRNA and non-rRNA reads into two separate files. I'll save both, but use the non-rRNA reads for downstream analyses.


0. Installing programs

I'm using sortmerna-2.1-linux-64.tar.gz from http://bioinfo.lifl.fr/RNA/sortmerna/ as the input file. Whoever wrote this deserves a medal, because it's pre-compiled! No installation tarball building necessary - just unzip it at the execute node and go.

_Note: as of Feb 2018, it looks like the available version is sortmerna-2.1-linux-64-multithread.tar.gz. I haven't tested this version, but see no reason why it shouldn't work. We're not using multithreading, though._

The other program used in this step is BBMap. Technically, this is a mapping program, but it has awesome tools for processing fastq files included. I'm using it in this step to split fastq files into equal parts. Today is your lucky day because this one doesn't need to be built either! Just download, unzip, and go. I'm using version 36.99 downloaded here: https://sourceforge.net/projects/bbmap/

_Note: as of Feb 2018, BBMap is up to version 37.90. I'm going to stick with the version I originally downloaded because it requires Java 6 instead of Java 7, but the newer version should work just fine. It does not look like there were changes to the functions I am using._

1. The first thing we need to do is split the giant fastq files into many smaller pieces. I'm starting with the reads that went through quality control at the JGI (extension .filter-MTF.fastq), located in /mnt/gluster/amlinz/GEODES_metaT.

From the submit node:

```{bash, eval = F}
# Make a new directory for the split files
mkdir /mnt/gluster/amlinz/GEODES_metaT_split/
# Alternatively, if you've done this before, just make sure this directory is empty
# rm /mnt/gluster/amlinz/GEODES_metaT_split/*

# Make a list of samples to run
for file in /mnt/gluster/amlinz/GEODES_metaT/*; do sample=$(basename $file |cut -d'.' -f1); echo $sample;done > samplenames.txt

# Don't want to run all of your samples just yet? The line below will keep just the first 3 files in the list.
# This is always a good idea if you're testing out a new script on CHTC. Once the small test in done, check the .log file to see what disk and memory requirements are needed and modify these in the submit file.

# head -3 samplenames.txt > test_samplenames.txt; mv test_samplenames.txt samplenames.txt

# Double check that these are the files you want to run!
cat samplenames.txt

# You should have both 00split_fastq.sub and 00split_fastq.sh in your home folder. The .sub file references the .sh file.
# I've set my executable to split files into 500,000 reads each, but you can change that.

# Check that your submit and executable files are referencing the right places, then submit your jobs:
condor_submit submits/00split_fastq.sub

# Check status with this command:
condor_q
# For a more detailed report of computers available while your job is idle:
# condor_q -analyze
# Something stuck or not going well? Remove jobs with:
# condor_rm -amlinz (username) or condor_rm -8222164 (job id)

# Check to see if there's anything in the error file
ls -ltr 00*.err

# Check to make sure the output is what you wanted:
ls -ltr /mnt/gluster/amlinz/GEODES_metaT_split/
find /mnt/gluster/amlinz/GEODES_metaT_split/ -type f
  
```

Here are the scripts used:
00splitfastqs.sub
```{bash, eval = F}
# 00split_fastq.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 00split_fastq_$(Cluster).log
error = 00split_fastq_$(Cluster)_$(Process).err
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/00split_fastq.sh
arguments = $(sample)
output = 00split_fastq_$(Cluster).out
#
# No files to transfer, since it's going to interact with Gluster instead of the submit node
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/BBMap_36.99.tar.gz
transfer_output_files = $(sample)-splitfiles.tar.gz
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory = 2 GB
request_disk = 12 GB
#
# Submit jobs
queue sample from samplenames.txt


```

00splitfastqs.sh
```{bash, eval = F}
#!/bin/bash
tar -xvzf BBMap_36.99.tar.gz

cp /mnt/gluster/amlinz/filtered/$1.filter-MTF.fastq.gz .
gzip -d $1.filter-MTF.fastq.gz

sed -i '/^$/d' $1.filter-MTF.fastq

maxreads=$((`wc -l < $1.filter-MTF.fastq` / 8 - 1))
startpoints=$(seq 0 500000 $maxreads)

for num in $startpoints;
  do endpoint=$(($num + 499999));
  bbmap/getreads.sh in=$1.filter-MTF.fastq id=$num-$endpoint out=$1-$endpoint.fastq overwrite=T;
  done

rm $1.filter-MTF.fastq
mkdir $1-splitfiles
mv $1*.fastq $1-splitfiles
tar cvzf $1-splitfiles.tar.gz $1-splitfiles
rm BBMap_36.99.tar.gz
rm -r bbmap

```

2. Sort that RNA! I'm using all of the provided databases as my alignment references.

```{bash, eval = F}
# Make some directories to store the output, or alternatively, empty these directories as above:
mkdir /mnt/gluster/amlinz/GEODES_nonrRNA_split/
mkdir /mnt/gluster/amlinz/GEODES_rRNA_split/

# Make a file that contains the paths to all of the file parts:
find /mnt/gluster/amlinz/GEODES_metaT_split/ -type f > path2splitfastqs.txt
cat path2splitfastqs.txt

# Submit the rRNA sorting jobs
condor_submit submits/01rRNA_removal.sub

#Bonus: my jobs got stuck in limbo. Here's how CHTC recommended fixing.
# Check to see where the jobs are:
condor_q -run -nobatch
# My stuck files were all on the same server, so likely a problem with that execute node, not my script.
# Move stuck jobs to hold and then restart:
condor_hold amlinz
condor_release amlinz

#On my full run, I ran 7,987 jobs from 85 original fastq files. 7,986 finished in 4.5 hours. 1 got stuck on a bad execute node and produced error to that effect.

# Check the output when all jobs have finished:
ls -ltr /mnt/gluster/amlinz/GEODES_nonrRNA/
ls -ltr /mnt/gluster/amlinz/GEODES_rRNA/
  
# Are the error files empty?
ls -ltr 01*.err
```

01rRNA_removal.sub
```{bash, eval = F}
# 01rRNA_removal.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 01rRNA_removal_$(Cluster).log
error = 01rRNA_removal_$(Cluster)_$(Process).err
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/01rRNA_removal.sh
arguments = $(fastqfile)
output = 01rRNA_removal_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/sortmerna-2.1-linux-64.tar.gz,/home/amlinz/GEODES_metaT_split/$(fastqfile)
transfer_output_files = $(fastqfile)-rRNA,$(fastqfile)-nonrRNA
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
request_cpus = 1
request_memory = 2GB
request_disk = 5GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue fastqfile from path2splitfastqs.txt

```

01rRNA_removal.sh
```{bash, eval = F}
#!/bin/bash
#Sort metatranscriptomic reads into rRNA and non-rRNA files

#Fastq files previously split into smaller pieces
name=$(basename $1 |cut -d'.' -f1)

#Unzip files
tar -xvf sortmerna-2.1-linux-64.tar.gz
gzip -d $name.fastq.gz
cd sortmerna-2.1-linux-64

#Index the rRNA databases
./indexdb_rna --ref ./rRNA_databases/silva-bac-16s-id90.fasta,./index/silva-bac-16s-db:\./rRNA_databases/silva-bac-23s-id98.fasta,./index/silva-bac-23s-db:./rRNA_databases/silva-arc-16s-id95.fasta,./index/silva-arc-16s-db:./rRNA_databases/silva-arc-23s-id98.fasta,./index/silva-arc-23s-db:./rRNA_databases/silva-euk-18s-id95.fasta,./index/silva-euk-18s-db:./rRNA_databases/silva-euk-28s-id98.fasta,./index/silva-euk-28s:./rRNA_databases/rfam-5s-database-id98.fasta,./index/rfam-5s-db:./rRNA_databases/rfam-5.8s-database-id98.fasta,./index/rfam-5.8s-db

#Run the sorting program
./sortmerna --ref ./rRNA_databases/silva-bac-16s-id90.fasta,./index/silva-bac-16s-db:./rRNA_databases/silva-bac-23s-id98.fasta,./index/silva-bac-23s-db:./rRNA_databases/silva-arc-16s-id95.fasta,./index/silva-arc-16s-db:./rRNA_databases/silva-arc-23s-id98.fasta,./index/silva-arc-23s-db:./rRNA_databases/silva-euk-18s-id95.fasta,./index/silva-euk-18s-db:./rRNA_databases/silva-euk-28s-id98.fasta,./index/silva-euk-28s:./rRNA_databases/rfam-5s-database-id98.fasta,./index/rfam-5s-db:./rRNA_databases/rfam-5.8s-database-id98.fasta,./index/rfam-5.8s-db --reads ../$name.fastq  --fastx --aligned ../$name-rRNA --other ../$name-nonrRNA --log -v -m 1 -a 1

cd ..
gzip *RNA.fastq
mkdir $1-rRNA
mkdir $1-nonrRNA
mv *-rRNA.fastq.gz $1-rRNA
mv *nonrRNA.fastq.gz $1-nonrRNA

#Remove files
rm sortmerna-2.1-linux-64.tar.gz
rm -r sortmerna-2.1-linux-64

```


3. Put everything back together. This is a pretty simple program - all it does it copy files generated from the same sample, concatenate them into a single file, count the number of lines, and zip it up. This is simple enough (and requires no installs, only bash) so I can run it on the submit node. It uses the previously generated samplenames.txt.

When running scripts on the script node, make sure to change permissions so that they are executable like so:
```{bash, eval = F}
chmod +x scripts/cat_RNA.sh
```

Then run with:
```{bash, eval = F}
./scripts/cat_RNA.sh
```

cat_RNA.sh:
```{bash, eval = F}

#!/bin/bash
#Concatenate sortmerna output
mv /home/amlinz/*-rRNA/* /home/amlinz/GEODES_rRNA_split
mv /home/amlinz/*-nonrRNA/* /home/amlinz/GEODES_nonrRNA_split
rmdir *RNA

gzip -d /home/amlinz/GEODES_nonrRNA_split/*
gzip -d /home/amlinz/GEODES_rRNA_split/*

cat /home/amlinz/samplenames.txt | while read line;
  do cat /home/amlinz/GEODES_nonrRNA_split/$line*nonrRNA.fastq > /home/amlinz/GEODES_nonrRNA/$line-nonrRNA.fastq;
  gzip /home/amlinz/GEODES_nonrRNA/$line-nonrRNA.fastq
  cat /home/amlinz/GEODES_rRNA_split/$line*rRNA.fastq > /home/amlinz/GEODES_rRNA/$line-rRNA.fastq;
  gzip /home/amlinz/GEODES_rRNA/$line-rRNA.fastq
done

```

Bonus: want to know how big each nonRNA file is? Run the script MT_size.sh in scripts/ to find out. Note: this will take awhile because it has to unzip and rezip each file.

```{bash, eval = F}
#!/bin/bash

for RNA in /mnt/gluster/amlinz/GEODES_nonrRNA/*;
        do sample=$(basename $RNA .fastq.gz);
        gzip -d $RNA;
        length=$(grep "@HISEQ" /mnt/gluster/amlinz/GEODES_nonrRNA/$sample.fastq | wc -l)
        echo $sample $length;
        gzip /mnt/gluster/amlinz/GEODES_nonrRNA/$sample.fastq;
        done > MT_size.txt

```

4. Clean up after yourself. Gluster is not meant for long term storage of files! Download these somewhere else and delete the copies on gluster once you're confident in the analysis.

On my computer:
Open up WinSCP and log into submit-4.chtc.wisc.edu. Download the GEODES_rRNA_ratios.txt file to my github repo, geodes/analyses/01rRNA_removal/. Download the most recent versions of the scripts used here while you're at it. I like to take a quick look at the results in R using the following code:

```{r, echo = T, fig.width = 4, fig.height = 10, eval = F}
library(ggplot2)
rRNA_ratio <- read.table("C:/Users/Alex/Desktop/geodes/analyses/01rRNA_removal/GEODES_rRNA_ratios.txt", header = F, sep = ",", colClasses = c("character"))
split1 <- strsplit(rRNA_ratio$V1, " ")
split2 <- strsplit(rRNA_ratio$V2, " ")
nonrRNA_count <- c()
rRNA_count <- c()
samplenames <- c()
for(i in 1:length(split1)){
  nonrRNA_count[i] <- split1[[i]][1]
  rRNA_count[i] <- split2[[i]][1]
  samplenames[i] <- substr(split2[[i]][2], start = 1, stop = 9)
}
nonrRNA_count <- as.numeric(nonrRNA_count)/4
rRNA_count <- as.numeric(rRNA_count)/4
percent_rRNA <- rRNA_count/(rRNA_count + nonrRNA_count) * 100
rRNA_ratios <- data.frame(samplenames, percent_rRNA)
ggplot(rRNA_ratios, aes(x = samplenames, y = percent_rRNA)) + theme_bw() + geom_bar(stat = "identity") + coord_flip()

```

On submit-4.chtc.wisc.edu:

```{bash, eval = F}
# Delete all the .log, .out, and .err files in your home directory
rm *.err
rm *.log
rm *.out

# Remove the rRNA ratios report and the sample name files
rm *.txt

```

You may be getting close to your file limit on gluster. Since we're not doing anything else with the rRNA files, download these to somewhere safe and remove from gluster. You can also remove the JGI QC filtered fastq files, as we'll be working with the nonrRNA files from now on. MAKE SURE EVERYTHING IS SAVED SOMEWHERE ELSE BEFORE DELETING FROM GLUSTER. 

Congratulations! You now have files of just nonrRNA reads from your metatranscriptomes, and are ready to run the next step.

##Non-redundant database building

####Goal of this analysis
So far, we've removed rRNA reads from the metatranscriptomes (see ../01rRNA_removal/). What I need to do next is map those reads to our database of reference genomes. But building that reference database is an important step itself - our results will only be as good as the database. I want something that includes every organism that might be in the metatranscriptomes without being too large or containing a bunch of identical genes that will confuse the mapper. The answer is a non-redundant database.

####Approach
My input genomes are as follows:

-GEODES SAGs - single amplifed genomes collected from water sampled on the same day as the metatranscriptomes. These should be excellent references. There are a few extra from Sparkling Lake water collected earlier in the summer because we don't have as many pre-existing genomes from that lake. 

-GEODES metagenome assemblies - DNA samples collected on the same day as the metatranscriptomes were sequenced and assembled. These should also be good references, but are not complete genomes and therefore have less taxonomic information. Later on in the workflow, I bin the assemblies to get better classifications for some of the contigs. They are also huge files. There are 4 additional Sparkling Lake samples from a previous grad student's project in 2009 - we sequenced these to get better references for things that may not have been as abundant in Sparkling (but still present) in the summer of 2016.

-ref MAGs and SAGs - Genomes from long-term time series and other projects that the McMahon Lab has already generated. They are primarily from Trout Bog and Lake Mendota, but there are a few Sparkling Lake SAGs in there. These are well annotated and classified, but may not be as good of references as those collected with the metatranscriptomes.

-refseq algae - We don't have pre-existing reference for eukaryotic algae, but we think they're important, particularly in Trout Bog. I included 6 algal genomes from the RefSeq database to try and capture some of those genes, but admittedly, they're predominantly marine and may not be great references. There are also contigs classified as algae in the metagenome assemblies.

That's a lot of data, so the first step is to pull out only coding regions. None of my RNA should match intergenic regions, so I don't need to map to those.

Next, I cluster coding regions so that I'm not putting duplicates in the reference database. Duplicates will result in a read being randomly assigned and each gene receiving half as many read counts. Clustering nearly identical genes prevents this issue AND drastically reduces the size of the database.

The tricky part in all of this is the gff files - these are files accompanying each genome that say where each gene is. They are in a different format for each type of input! A lot of the code in this section is devoted to switching file formats.

0. Installations. We'll need Python with specific packages pre-installed. This one we do actually have to compile. Here is an example of the interactive script used to start the build mode. I'm using Python version 2.7.13 from https://www.python.org/downloads/. 

install_things.sub
```{bash, eval = F}
#install_things.sub
#
universe = vanilla
# Name the log file:
log = install_things.log

# Name the files where standard output and error should be saved:
output = install_things.out
error = install_things.err

# If you wish to compile code, you'll need the below lines.
#  Otherwise, LEAVE THEM OUT if you just want to interactively test!
+IsBuildJob = true
requirements = (OpSysMajorVer =?= 7) && ( IsBuildSlot == true )

# Indicate all files that need to go into the interactive job session,
# This is the file downloaded from the developers of the program
transfer_input_files = zipped/Python-2.7.13.tgz

# It's still important to request enough computing resources. The below
#  values are a good starting point, but consider your file sizes for an
#  estimate of "disk" and use any other information you might have
#  for "memory" and/or "cpus".

request_cpus = 1
request_memory = 8GB
request_disk = 4GB

queue
```

You start an interactive job by running:
```{bash, eval = F}
condor_submit -i submits/install_things.sub
```

Here's the installation instructions for python with modules installed.
```{bash, eval = F}
mkdir python
tar -xvf Python-2.7.13.tgz
cd Python-2.7.13
./configure --prefix=$(pwd)/../python
make
make install
cd ..
ls python
ls python/bin

export PATH=$(pwd)/python/bin:$PATH
wget https://bootstrap.pypa.io/get-pip.py
python get-pip.py
pip install numpy
pip install pandas
pip install BCBio

tar -czvf python.tar.gz python/
exit

```

In each script, you'll need to tell the computer where Python is located by setting the PATH variable. Add the following lines to your scripts immediately after unzipping the python tarball. This also ensures that your version of Python with your desired add-ons is being used instead of whatever is installed on that execute node.

```{bash, eval = F}
#Update the path variable
mkdir home
export PATH=$(pwd)/python/bin:$PATH
export HOME=$(pwd)/home
```

I also need a program called GenomeTools for formatting gff files. In the interactive submit file, change the name of the input file to the name of the downloaded GenomeTools tarball. I'm using version 1.5.9 downloaded here: http://genometools.org/pub/

```{bash, eval = F}
tar -xvzf genometools-1.5.9.tar.gz
cd genometools-1.5.9
make cairo=no
make prefix=$(pwd)/../genometools/ cairo=no install
cd ..
tar cvzf genometools.tar.gz genometools-1.5.9
exit
```

In every executable that needs GenomeTools, include this line after unzipping to set the PATH.
```{bash, eval = F}
export PATH=$(pwd)/genometools/bin:$PATH
```

Lastly, we need a program to cluster genes. I'm using cd-hit version 4.6.8 from https://github.com/weizhongli/cdhit/releases. Just a bunch of make commands here, nothing fancy.

```{bash, eval = F}
tar xvf cd-hit-v4.6.8-2017-0621-source.tar.gz --gunzip
cd cd-hit-v4.6.8-2017-0621
make
cd cd-hit-auxtools
make

cd ../..
tar czvf cd-hit.tar.gz cd-hit-v4.6.8-2017-0621
exit
```

No variable setting necessary, we'll call cd-hit directly from our home directory when it's needed.

1. Gather the genomes. The GEODES metagenome assemblies and SAGs and the time series MAGs and SAGs can be found on either IMG, JGI's Genome Portal, or the McMahon Lab fileshare. The algae files are from NCBI's refseq. For each genome, you'll need a .fna or fasta file (for the entire genome) and a .gff file. For the metagenome assemblies, you'll also need the .phylodist file, the .product_names file and the .COGs file.

Put the metagenome assembly files on Gluster. Put phylodist files in /mnt/gluster/amlinz/metagenome_assemblies/phylogeny, .fna in fastas, .gff in gff, and .product_names in product_names.  Put the MAGS and SAGS (from both the time series and GEODES, they're in the same format, yay!) in your home folder in a directory called ref_MAGs_SAGs/fastas and ref_MAGs_SAGs/gffs.

2. Classify the metagenome assemblies. The phylodist file contains gene level classifications, but these are notoriously inaccurate. We're going to compare gene classifications at the contig level to either get a consensus classfication or declare it unclassifiable. 

You'll need a file called metagenome.txt in your folder that is a list of the metagenome names, no file extensions or paths. In my case, this step runs 8,048 jobs and finished overnight.

```{bash, eval = F}
# In the previous rRNA sorting step, you prepared a list of files for input, split metatranscriptomes into smaller pieces, processed each piece, and put them back together. We're following a similar format here. Please go back to the rRNA sorting section for info on the condor commands and how to check that the output is ok.

# Make a list of contigs to classify. Make sure to change permissions to executable on this script.
./scripts/prephylodist.sh

# Run the classification step. This uses a python script in scripts/ courtesy of Sarah Stevens!
# If you're running this for the first time, modify the list of files to run to only include 3 or so jobs as a test, like we did in the rRNA sorting step. No matter how sure you are that it's set up correctly, you don't want to risk 8,000 failed jobs because of a typo.
condor_submit submits/02phylodist.sub

# Recombine the results.
./scripts/postphylodist.sh

# Check the output, backup a copy of the phylodist results on another computer, and clean up the home directory
rm *err
rm *log
rm *out
rm *.contig.classification.perc70.minhit3.txt 
```

Here are the contents of the scripts used.

prephylodist.sh:
```{bash, eval = F}
#!/bin/bash

mkdir contig_lists
cat metagenome.txt | while read line;
  do awk '{print substr($1,1,18)}' /mnt/gluster/amlinz/metagenome_assemblies/phylogeny/$line.assembled.phylodist | sort | uniq >   /home/amlinz/$line-contigs.txt;
  split -l 1500 -a 4 -d $line-contigs.txt contig_lists/$line-contigs;
done

# Make a list of files to run
ls contig_lists > metaG_contigs.txt

```

02phylodist.sub:
```{bash, eval = F}
# 02phylodist.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 02phylodist_$(Cluster).log
error = 02phylodist_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (OpSysMajorVer == 7) && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/02phylodist.sh
arguments = $(contigs)
output = 02phylodist_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/python.tar.gz,scripts/classifyWphylodist_contigs.py,contig_lists/$(contigs),GEODES168.assembled.phylodist
transfer_output_files = $(contigs).contig.classification.perc70.minhit3.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 4GB
request_disk = 1GB
#
# run from list
queue contigs from metaG_contigs.txt

```

02phylodist.sh:
```{bash, eval = F}

#!/bin/bash
#Classify contigs based on their gene's USEARCH hits provided by JGI
metaG=$(echo $1 | head -c 9)
cp /mnt/gluster/amlinz/metagenome_assemblies/phylogeny/$metaG.assembled.phylodist .
cat $1 | while read line
  do grep $line $metaG.assembled.phylodist;
  done > $1.phylodist

#add header
echo $'locus_tag\thomolog_gene_oid\thomolog_taxon_oid\tpercent_identity\tlineage' | cat - $1.phylodist > temp.phylodist && mv temp.phylodist $1.phylodist

tar xvzf python.tar.gz
#Update the path variable
mkdir home
export PATH=$(pwd)/python/bin:$PATH
export HOME=$(pwd)/home

chmod +x classifyWphylodist_contigs.py

python classifyWphylodist_contigs.py -pd $1.phylodist -pc .70 -hm 3 -conlen 18

rm *phylodist
rm *py
rm -rf python/
rm -r home/
rm python.tar.gz
```

classifyWphylodist_contigs.py:
```{python, eval = F, python.reticulate = F}

import pandas as pd, sys, os, argparse

"""classifyWPhylodist.py  classifys contigs, for each taxonomic level it takes the classificaiton with the most hits,
        removes any not matching hits for the next level, also returns the number and avg pid for those hits"""

__author__ = "Sarah Stevens"
__email__ = "sstevens2@wisc.edu"


# Read in args function
def parseArgs():
        parser = argparse.ArgumentParser(description='classifyWPhylodist_contig.py: classifies each contig from an IMG metagenome annotated phylodist file.')
        parser.add_argument('--phylodist','-pd' , action='store', dest='inname', type=str, required=True, metavar='PhylodistFile', help="Phylodist file from IMG annotation of metagenome")
        parser.add_argument('--percent_cutoff','-pc', action='store', dest='perc_co', default=.70, type=float, help='Minimum percentage of hits that much match at each taxon rank to use classification. DEFAULT: .70')
        parser.add_argument('--hit_minimum','-hm', action='store', dest='hit_min', default=3, type=int, help='Minium number of hits that must match at each taxon rank to use classification. DEFAULT: 3')
        parser.add_argument('--printVals', '-pv', action='store_true', dest='wvals', default=False, help='Include this flag if you would like it to print the percent matching, AAI, and num hits for each match.')
        parser.add_argument('--contignamelen','-conlen', action="store", dest='conlen', default=17, type=int, help='Num of characters from locus_tag to take pull for contig name. DEFAULT: 17')
        parser.add_argument('--alwaysPrintStop','-aps', action='store_true', dest='printStop', default=False, help='Include this flag if you would like it to always print the code, by default only prints stopcode if not classified to kingdom.')
        args=parser.parse_args()
        return args.inname, args.perc_co, args.hit_min, args.wvals, args.conlen, args.printStop

# Read in args
inname, perc_co, hit_min, wvals, conlen, printStop  = parseArgs()

phylodist = pd.read_table(inname)

# Setting contig column
phylodist['contig']=phylodist['locus_tag'].str[:conlen]

# Splitting taxonomy out into multipule cols and fixing the variation in number of cols
phylodist['numTaxons'] = phylodist['lineage'].str.count(';')
# check that 7 and 8 are the only #'s of occurrences
assert (phylodist[(phylodist.numTaxons != 8) & (phylodist.numTaxons != 7)].empty == True), \
                "lineage column has too many or two few ';' seps"
# new df for the 7 occurrences of ';', which is 8 values
eig_phylodist = phylodist[(phylodist.numTaxons == 7)]
if eig_phylodist.empty != True:
        eig_taxon_ranks=['Kingdom','Phylum','Class','Order','Family','Genus','Species','Taxon_name']
        eig_phylodist[eig_taxon_ranks]=eig_phylodist['lineage'].apply(lambda x: pd.Series(x.split(';')))
        eig_phylodist['substrain']=''
# new df for the 8 occurrences of ';', which is nine values
nin_phylodist = phylodist[(phylodist.numTaxons == 8)]
if nin_phylodist.empty != True:
        nin_taxon_ranks=['Kingdom','Phylum','Class','Order','Family','Genus','Species','Taxon_name','substrain']
        nin_phylodist[nin_taxon_ranks]=nin_phylodist['lineage'].apply(lambda x: pd.Series(x.split(';')))
# putting them back into one df or assigning the one to the phylodist df
if (eig_phylodist.empty != True) & (nin_phylodist.empty !=True):
        phylodist = pd.concat([eig_phylodist, nin_phylodist])
elif (eig_phylodist.empty == True) & (nin_phylodist.empty !=True):
        phylodist = nin_phylodist
elif (eig_phylodist.empty != True) & (nin_phylodist.empty == True):
        phylodist = eig_phylodist
else:
        print("You don't have any 8 or 9 taxon genomes")
        sys.exit(2)

# Setting up output
percname=format(float(perc_co), '.2f')[-2:]
outname=os.path.splitext(inname)[0]+'.contig.classification.perc{0}.minhit{1}.txt'.format(percname,hit_min)
if wvals:
        outname=os.path.splitext(inname)[0]+'.contig.classification.perc{0}.minhit{1}.wvals.txt'.format(percname,hit_min)
output=open(outname,'w')
#output.write(inname+'\n')
if phylodist.empty: # if there are no hits in phylodist file
        print('Phylodist empty!  This maybe because it was subsetted into phylocogs and there were none.')
        output.write('NO CLASSIFICATION BASED ON GIVEN PHYLODIST\n')
        sys.exit(0)

# Values for percent identity
rank_co_dict = {'Kingdom':20,'Phylum':45,'Class':49,'Order':53,'Family':61,'Genus':70,'Species':90,'Taxon_name':97}


for contig in phylodist['contig'].unique():
        tempphylodist=phylodist[phylodist['contig'] == contig]
        contig_classification_str=""
        output.write(contig+'\t')
        totGenes=len(tempphylodist)
        for rank in eig_taxon_ranks:  # this will never get down to the extra last eukaryotic taxon that is sometimes in eukaryotic classifications
                # Getting taxon, at that level, hit the most and the number of hits
                perc=tempphylodist.groupby(rank).size()/float(totGenes) # percent of times each classification, had to add forced float for python2
                counts=tempphylodist.groupby(rank).size()
                max_ct_value=counts.max() # number of hits the classification with the most hits had
                max_ct_perc=perc.max() # percentage of hits the classification with the most hits had
                max_ct_taxon=perc.idxmax(axis=1) # classificaiton hit the most at this rank
                averages=tempphylodist.groupby(rank).mean().reset_index()[[rank,'percent_identity']] #getting average pid for best classifcation
                max_ct_avg=averages.loc[averages[rank]==max_ct_taxon, 'percent_identity'].iloc[0]
                result=(max_ct_taxon, round(max_ct_perc, 2), round(max_ct_avg, 2), max_ct_value)
                if wvals:
                        contig_classification_str='{}({},{},{});'.format(result[0],result[1],result[2], result[3])
                else:
                        contig_classification_str='{};'.format(result[0])
                tempphylodist=tempphylodist[tempphylodist[rank]==max_ct_taxon] # removing any hits which don't match the classification at this level
                rank_co = rank_co_dict[rank]
                if (max_ct_perc>perc_co and max_ct_value>hit_min and max_ct_avg>rank_co):
                        output.write(contig_classification_str)
                else:
                        if rank == 'Kingdom':
                                stopcode = 'NO CLASSIFICATION '
                                if result[3]<=hit_min:
                                        stopcode += 'MH' # *M*in *H*its too low aka 'NO CLASSIFICATION DUE TO TOO FEW HITS LEFT ON CONTIG AT THIS LEVEL'
                                elif max_ct_avg>rank_co:
                                        stopcode += 'LP' # *L*ow *P*ID aka 'NO CLASSIFICATION DUE TO TOO LOW PID FOR CLASSICICATION AT THIS LEVEL'
                                elif max_ct_perc>perc_co:
                                        stopcode += 'PM' # *P*ercent *M*atching too low aka NO CLASSIFICATION DUE TO TOO LOW PERCENT MATCHING FOR CLASSICICATION AT THIS LEVEL'
                                output.write(stopcode)
                        elif printStop:
                                stopcode = ''
                                if result[3]<=hit_min:
                                        stopcode += 'MH' # *M*in *H*its too low aka 'NO CLASSIFICATION DUE TO TOO FEW HITS LEFT ON CONTIG AT THIS LEVEL'
                                elif max_ct_avg>rank_co:
                                        stopcode += 'LP' # *L*ow *P*ID aka 'NO CLASSIFICATION DUE TO TOO LOW PID FOR CLASSICICATION AT THIS LEVEL'
                                elif max_ct_perc>perc_co:
                                        stopcode += 'PM' # *P*ercent *M*atching too low aka NO CLASSIFICATION DUE TO TOO LOW PERCENT MATCHING FOR CLASSICICATION AT THIS LEVEL'
                                output.write(stopcode)
                        break
        output.write('\n')

output.close()
```

postphylodist.sh
```{bash, eval = F}
#!/bin/bash

mkdir phylodist_results
cat GEODES005-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES005.contig.classification.perc70.minhit3.txt

cat GEODES006-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES006.contig.classification.perc70.minhit3.txt

cat GEODES057-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES057.contig.classification.perc70.minhit3.txt

cat GEODES058-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES058.contig.classification.perc70.minhit3.txt

cat GEODES117-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES117.contig.classification.perc70.minhit3.txt

cat GEODES118-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES118.contig.classification.perc70.minhit3.txt

cat GEODES165-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES165.contig.classification.perc70.minhit3.txt

cat GEODES166-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES166.contig.classification.perc70.minhit3.txt

cat GEODES167-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES167.contig.classification.perc70.minhit3.txt

cat GEODES168-contigs*.contig.classification.perc70.minhit3.txt > phylodist_results/GEODES168.contig.classification.perc70.minhit3.txt

```

3. Process the MAGs and SAGs. I want to extract coding regions from these genomes. I need to reformat the gff files just enough to extract the coding regions (CDS), but I'm not actually going to use them after this, so I don't need to save the reformatted gffs. 
The README.csv file comes from the fileshare and has phylogeny of our time series MAGs. I manually added the GEODES SAGs information to this using data from IMG. Each genome is its own job; no splitting needed. While parsing the gff and the CDS regions, I'm also going to pull out gene information from the gff file that I'll need later, such as product name. Josh Hamilton helped me write the Python script to do this efficiently - thanks Josh! This steps runs 330 jobs in about 20 minutes.

```{bash, eval = F}
./scripts/refMAGs_SAGs_list.sh
condor_submit submits/03refMAGs_SAGs.sub
```

refMAGs_SAGs_list.sh
```{bash, eval = F}
#!/bin/bash

for file in ref_MAGs_SAGs/fastas/*;do name=$(basename $file | cut -d'.' -f1); echo $name; done > refMAGs_SAGs_list.txt

#For testing, uncomment the following line:
#head -2 refMAGs_SAGs_list.txt > testrefMAGs_SAGs_list.txt

```

03refMAGs_SAGs.sub
```{bash, eval = F}
# 03refMAGs_SAGs.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 03refMAGs_SAGs_$(Cluster).log
error = 03refMAGs_SAGs_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Arch == "X86_64")
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/03refMAGs_SAGs.sh
arguments = $(samplename)
output = 03refMAGs_SAGs_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = /home/amlinz/zipped/genometools.tar.gz,/home/amlinz/ref_MAGs_SAGs/gffs/$(samplename).gff,/home/amlinz/ref_MAGs_SAGs/Readme.csv,scripts/ref_MAGs_SAGs_parsing.py,zipped/python.tar.gz,ref_MAGs_SAGs/fastas/$(samplename).fna
transfer_output_files = CDS.$(samplename).fna,$(samplename).table.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 4GB
request_disk = 2GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue samplename from /home/amlinz/refMAGs_SAGs_list.txt

```

03refMAGs_SAGs.sh
```{bash, eval = F}
#!/bin/bash
#Install genome tools and python
tar xvzf genometools.tar.gz
tar xvzf python.tar.gz

#Update the path variable
mkdir home
export PATH=$(pwd)/python/bin:$PATH
export HOME=$(pwd)/home
export PATH=$(pwd)/genometools/bin:$PATH

#Remove CRISPRs
grep -v "CRISPR" $1.gff > temp.gff && mv temp.gff $1.gff
#Setup and run python script
chmod +x ref_MAGs_SAGs_parsing.py
python ref_MAGs_SAGs_parsing.py $1

#Remove all the duplicate gff-version lines
grep -v "##gff-version 3" $1.parsed.gff > int1.gff
# Move sequence region lines to top of file
grep "##sequence-region" int1.gff > sequence_regions.gff
grep -v "##sequence-region" int1.gff > not_sequence_regions.gff

# Put it all back together and clean up
echo '##gff-version 3' | cat - sequence_regions.gff not_sequence_regions.gff > $1.fixed.gff
gt gff3 -sort yes -tidy -retainids -o sorted.$1.gff $1.fixed.gff #clean up the the gff sorter

# Extract the coding regions from the fasta file
gt extractfeat -type CDS -seqid no -retainids yes -seqfile $1.fna -matchdescstart sorted.$1.gff >  CDS.$1.fna

rm *tar.gz
rm *csv
rm *py
rm -r genometools
rm -r home
rm -rf python
rm $1.fna
rm $1.fna.*
rm *.gff

```

ref_MAGs_SAGs_parsing.py
```{python, eval = F, python.reticulate = F}
###############################################################################
# CodeTitle.py
# Copyright (c) 2017, Joshua J Hamilton and Alex Linz
# Affiliation: Department of Bacteriology
#              University of Wisconsin-Madison, Madison, Wisconsin, USA
# URL: http://http://mcmahonlab.wisc.edu/
# All rights reserved.
################################################################################
# Make table of info from gff files
################################################################################

#%%#############################################################################
### Import packages
################################################################################

from BCBio import GFF # Python package for working with GFF files
import pandas
import os
import sys

#%%#############################################################################
### Define input files
################################################################################

genome = sys.argv[1]
#genome = '2582580615'
taxonFile = 'Readme.csv'
inputGff = genome + '.gff'
outputGff = genome + '.parsed.gff'
outputTable = genome + '.table.txt'

#%%#############################################################################
### Update the inputGff file. Replace ID with 'locus tag' field
### Make a separate table with taxonomy and product name info
################################################################################

# Store the classification file as a dictionary

taxonFile = "Readme.csv"
readme = pandas.read_csv(taxonFile, header = none, names = ['IMG OID', 'SAGNAME', 'Phylum', 'Class', 'Order', 'Lineage', 'Clade', 'Tribe', 'ProcessingNotes', 'unused1', 'unused2', 'unused3', 'unused4', 'unused5'])
readme = readme.fillna(value='')
readme["TaxString"] = readme['Phylum'] + ';' + readme['Class'] + ';' + readme['Order'] + ';' + readme['Lineage'] + ';' + readme['Clade'] + ';' + readme['Tribe']
readme['IMG OID'] = readme['IMG OID'].apply(str)
taxonDict = readme.set_index('IMG OID').to_dict()['TaxString']

# Read in the GFF file
# Each record contains all sequences belonging to the same contig
# For each sequence within the record, replace the ID with the locus_tag

inFile = open(inputGff, 'r')
outFile1 = open(outputGff, 'w')
outFile2 = open(outputTable, 'w')

for record in GFF.parse(inFile):
    for seq in record.features:
        seq.id = seq.qualifiers['locus_tag'][0] # this is a list for some reason
        seq.qualifiers['ID'][0] = seq.id + "_" + genome
        if 'product' in seq.qualifiers.keys():
            product = seq.qualifiers['product'][0]
        else:
            product = 'None given'
        del seq.qualifiers['locus_tag']

        taxonomy = taxonDict[genome]
        outFile2.write(seq.qualifiers['ID'][0]+'\t'+genome+'\t'+str(taxonomy)+'\t'+product+'\n')
    GFF.write([record], outFile1)

inFile.close()
outFile1.close()
outFile2.close()

```

Note: exclude the internal standard files, or it will get held

4. Parse the algal genomes. Same idea as with the MAGs and SAGs - extract coding regions using the gff file, formatted as necessary, and produce a key of information from each gene.

The algal genomes used are:
GCF_000149405.2_ASM14940v2_genomic      Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana
GCF_000240725.1_ASM24072v1_genomic      Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana
GCF_000150955.2_ASM15095v2_genomic      Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum
GCF_000315625.1_Guith1_genomic  Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta
GCF_000186865.1_v_1.0_genomic   Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens
GCF_000372725.1_Emiliana_huxleyi_CCMP1516_main_genome_assembly_v1.0_genomic    Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi

This step runs 6 jobs in 15 minutes.

```{bash, eval = F}
./scripts/algae_list.sh
condor_submit submits/04algae.sub

```

algae_list.sh
```{bash, eval = F}
#!/bin/bash

for file in refseq_algae/fastas/*;do name=$(basename $file .fna.gz); echo $name; done > algae_list.txt

#For testing, uncomment the following lines:
#head -2 algae_list.txt > temp.txt
#mv temp.txt algae_list.txt

```

04algae.sub
```{bash, eval = F}

# 04algae.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 04algae_$(Cluster).log
error = 04algae_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (OpSysMajorVer == 7)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/04algae.sh
arguments = $(samplename)
output = 04algae_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/python.tar.gz,zipped/genometools.tar.gz,refseq_algae/fastas/$(samplename).fna.gz,refseq_algae/gffs/$(samplename).gff.gz,refseq_algae/algae_phylogeny.txt,scripts/ref_algae_parsing.py
transfer_output_files = CDS.$(samplename).fna,$(samplename).table.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
# Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory = 4GB
request_disk = 2GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue samplename from /home/amlinz/algae_list.txt

```

04algae.sh
```{bash, eval = F}

#!/bin/bash
#Install genome tools and python
tar xvzf genometools.tar.gz
tar xvzf python.tar.gz

#Update the path variable
mkdir home
export PATH=$(pwd)/python/bin:$PATH
export HOME=$(pwd)/home
export PATH=$(pwd)/genometools/bin:$PATH

gzip -d $1.gff.gz
gzip -d $1.fna.gz

#Remove CRISPRs
sed -i '/CRISPR/d' $1.gff

#Split up gff file
grep "##\|#!" $1.gff > top_of_file.txt
grep "CDS" $1.gff > bottom_of_file.txt
awk -v OFS='\t' '{print $1,$2,$3,$4,$5,$6,$7,$8}' bottom_of_file.txt > part1.txt;
awk -F '\t' '{print $9}' bottom_of_file.txt > part2.txt;
#Get IDs
awk -F ";" '{print $1}' part2.txt > IDs.txt;
#Get start location
awk '{print $4}' bottom_of_file.txt > start.txt;

#look up phylogeny and make that column, too
rows=$(wc -l bottom_of_file.txt | awk '{print $1}')
assignment=$(grep -n $1 algae_phylogeny.txt | awk '{print $2}')
yes $assignment | head -n $rows > classification.txt
awk -F ',' '{print  $6}' classification.txt > species.txt

#Pull out product tags
awk -F 'product=' '{print $2}' part2.txt | awk -F ';' '{print $1}' > products.txt
#Replace blank lines with "None given"
sed -i -e 's/^$/None given/' products.txt
sed -i -e 's/^/product=/' products.txt

#Put the columns back together
paste -d "\t'" part1.txt IDs.txt > cat1.txt;
paste -d "_" cat1.txt start.txt > cat2.txt;
paste -d "_" cat2.txt species.txt > cat3.txt;
paste -d ";" cat3.txt products.txt > newbottom.txt

#Put the sequence region tags back on top
cat top_of_file.txt newbottom.txt > new.gff;

#Sort with genometools
gt gff3 -sort yes -tidy -retainids -o sorted.$1.gff new.gff;
# Extract the coding regions from the fasta file
gt extractfeat -type CDS -seqid no -retainids yes -seqfile $1.fna -matchdescstart sorted.$1.gff >  CDS.$1.fna

#Run the python script to build the key table

chmod +x ref_algae_parsing.py
python ref_algae_parsing.py $1

rm *tar.gz
rm algae_phylogeny.txt
rm *py
rm -r genometools
rm -r home
rm -rf python
rm $1.fna
rm $1.fna.*
rm *.gff
rm bottom_of_file.txt
rm top_of_file.txt
rm part1.txt
rm part2.txt
rm IDs.txt
rm classification.txt
rm products.txt
rm cat*txt
rm species.txt
rm start.txt
rm newbottom.txt

```

ref_algae_parsing.py
```{bash, eval = F, python.reticulate = F}
###############################################################################
# ref_algae_parsing.py
# Copyright (c) 2017, Joshua J Hamilton and Alex Linz
# Affiliation: Department of Bacteriology
#              University of Wisconsin-Madison, Madison, Wisconsin, USA
# URL: http://http://mcmahonlab.wisc.edu/
# All rights reserved.
################################################################################
# Make table of info from gff files
################################################################################

#%%#############################################################################
### Import packages
################################################################################

from BCBio import GFF # Python package for working with GFF files
import pandas
import os
import sys

#%%#############################################################################
### Define input files
################################################################################

genome = sys.argv[1]
#genome = "GCF_000149405.2_ASM14940v2_genomic"
taxonFile = 'algae_phylogeny.txt'
inputGff = "sorted." + genome + '.gff'
outputGff = genome + '.parsed.gff'
outputTable = genome + '.table.txt'

#%%#############################################################################
### Update the inputGff file. Replace ID with ID + species name (otherwise genes are just numbered and you can't tell which genome they came from)
### Make a separate table with taxonomy and product name info
################################################################################

# Store the classification file as a dictionary

readme = pandas.read_table(taxonFile, names = ["Genome", "Taxonomy"])
taxonDict = readme.set_index('Genome').to_dict()['Taxonomy']
taxonomy  = taxonDict[genome]

# Read in the GFF file
# Extract product information
# Rename genes including species name because they are just numbered

inFile = open(inputGff, 'r')
outFile2 = open(outputTable, 'w')

limit_info = dict(gff_type = ["CDS"],)
for record in GFF.parse(inFile, limit_info = limit_info):
    for seq in record.features:
        seq.id = seq.qualifiers['ID'][0]
        product = seq.qualifiers['product'][0]
        outFile2.write(seq.id+'\t'+genome+'\t'+str(taxonomy)+'\t'+product+'\n')

inFile.close()
outFile2.close()


```

6. Last but definitely not least, process the metagenome assemblies. It's the same deal as before, but now we'll be using squid to transfer files. The squid server is used for files between 100MB and 1GB that are referenced by many jobs at once. Since the metagenome assemblies are so big, I'm splitting them up by contigs. 

You'll notice there are multiple submit files for this step. Each one references a different metagenome. If I'd wanted to combine all this into one submission, I would have needed to set a 2nd variable for metagenome to send over the correct files, or send over the metagenome data files for every metagenome, even if the job only needs one. Separate submissions seemed like the easiest way to go. Each job still uses the same executable, runs 5-10 jobs, and completes in about 1 hour. They can be started at the same time (but make sure to do a quick test, first - maybe just run one to start).

```{bash, eval = F}

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
```

split_metaG_gffs.sh
```{bash, eval = F}
#!/bin/bash

mkdir metaG_gffs
cd metaG_gffs
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES005.assembled.gff GEODES005.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES006.assembled.gff GEODES006.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES057.assembled.gff GEODES057.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES058.assembled.gff GEODES058.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES117.assembled.gff GEODES117.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES118.assembled.gff GEODES118.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES166.assembled.gff GEODES165.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES166.assembled.gff GEODES166.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES167.assembled.gff GEODES167.
split -500000 /mnt/gluster/amlinz/metagenome_assemblies/gff/GEODES168.assembled.gff GEODES168.

# make list of files to run
ls GEODES005* > ../005metaG_gffs.txt
ls GEODES006* > ../006metaG_gffs.txt
ls GEODES057* > ../057metaG_gffs.txt
ls GEODES058* > ../058metaG_gffs.txt
ls GEODES117* > ../117metaG_gffs.txt
ls GEODES118* > ../118metaG_gffs.txt
ls GEODES165* > ../165metaG_gffs.txt
ls GEODES166* > ../166metaG_gffs.txt
ls GEODES167* > ../167metaG_gffs.txt
ls GEODES168* > ../168metaG_gffs.txt
cd ..

```

05.1metaG_gffs.sub
```{bash, eval = F}
# 05metaG_gffs.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 05metaG_gffs_$(Cluster).log
error = 05metaG_gffs_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Arch == "X86_64") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/05metaG_gffs.sh
arguments = $(samplename)
output = 05metaG_gffs_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/python.tar.gz,zipped/genometools.tar.gz,scripts/metaG_parsing.py,metaG_gffs/$(samplename),http://proxy.chtc.wisc.edu/SQUID/amlinz/GEODES005.datafiles2.tar.gz

transfer_output_files = CDS.$(samplename).fna,$(samplename).table.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
# Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory = 4GB
request_disk = 2GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue samplename from 005metaG_gffs.txt

```

05metaG_gffs.sh
```{bash, eval = F}
#!/bin/bash
tar xvzf genometools.tar.gz
tar xvzf python.tar.gz

#Update the path variable
mkdir home
export PATH=$(pwd)/python/bin:$PATH
export HOME=$(pwd)/home
export PATH=$(pwd)/genometools/bin:$PATH

metaG=$(echo $1 | cut -c1-9)
tar xvzf $metaG.datafiles2.tar.gz
gzip -d $metaG.assembled.fna.gz

mv $1 $metaG.assembled.gff
chmod +x metaG_parsing.py

awk -F'\t' -vOFS='\t' '{gsub("-1", "-", $7); gsub("1", "+", $7); print}' $metaG.assembled.gff > f1_$metaG.assembled.gff
echo '##gff-version 3' | cat - f1_$metaG.assembled.gff > temp && mv temp $metaG.assembled.gff

python metaG_parsing.py $metaG

mv $metaG.parsed.gff $1.parsed.gff
mv $metaG.table.txt $1.table.txt

gt gff3 -sort yes -tidy -retainids -o sorted.$1.gff $1.parsed.gff #clean up the the gff sorter

# Extract the coding regions from the fasta file
gt extractfeat -type CDS -seqid no -retainids yes -seqfile $metaG.assembled.fna -matchdescstart sorted.$1.gff >  CDS.$1.fna


rm *minhit3.txt
rm *product_names
rm $metaG.assembled.fna
rm *gff
rm metaG_parsing.py
rm *tar.gz
rm -r genometools
rm -r home
rm -rf python

```

metaG_parsing.py
```{python, eval = F, python.reticulate = F}
###############################################################################
# CodeTitle.py
# Copyright (c) 2017, Joshua J Hamilton and Alex Linz
# Affiliation: Department of Bacteriology
#              University of Wisconsin-Madison, Madison, Wisconsin, USA
# URL: http://http://mcmahonlab.wisc.edu/
# All rights reserved.
################################################################################
# Make table of info from gff files
################################################################################

#%%#############################################################################
### Import packages
################################################################################

from BCBio import GFF # Python package for working with GFF files
import pandas
import os
import sys

#%%#############################################################################
### Define input files
################################################################################

genome = sys.argv[1]
#genome = 'GEODES006'
taxonFile = genome + '.contig.classification.perc70.minhit3.txt'
productFile = genome + '.assembled.product_names'
inputGff = genome + '.assembled.gff'
outputGff = genome + '.parsed.gff'
outputTable = genome + '.table.txt'

#%%#############################################################################
### Update the inputGff file. Replace ID with 'locus tag' field
### Make a separate table with taxonomy and product name info
################################################################################

# Store the classification file as a dictionary

readme = pandas.read_csv(taxonFile, sep='\t', header = None)
readme.columns = ['Contig', 'TaxString']
taxonDict = readme.set_index('Contig').to_dict()['TaxString']

# Store the product info as a dictionary

product_table = pandas.read_csv(productFile, sep = '\t')
product_table.columns = ['Gene', 'Product', 'KO']
productDict = product_table.set_index('Gene').to_dict()['Product']

# Read in the GFF file
# Each record contains all sequences belonging to the same contig
# For each sequence within the record, replace the ID with the locus_tag

inFile = open(inputGff, 'r')
outFile1 = open(outputGff, 'w')
outFile2 = open(outputTable, 'w')

limit_info = dict(gff_type = ["CDS"],)
for record in GFF.parse(inFile, limit_info=limit_info):
    for seq in record.features:
        seq.id = seq.qualifiers['locus_tag'][0] # this is a list for some reason
        seq.qualifiers['ID'][0] = seq.id + "_" + genome
        del seq.qualifiers['locus_tag']

        taxonomy = taxonDict.get(seq.id[:18])
        product = productDict.get(seq.id)
        outFile2.write(seq.qualifiers['ID'][0]+'\t'+seq.id[:18]+'\t'+str(taxonomy)+'\t'+str(product)+'\n')
    GFF.write([record], outFile1)

inFile.close()
outFile1.close()
outFile2.close()
```

7. We're almost there! The last step is to combine all the outputs from jobs 03-05.10, cluster, and process the clustering output a bit. You should already have CD-HIT installed as above. Our goal here is to make the non-redundant database .fna file with a .gff file to match. CD-HIT does not process or produce gff files, and we really need one for counting reads later, so we'll have to build one ourselves. This is a pretty intensive process, so we build the gff file in pieces and put it back together at the end.

I'm clustering at 97% ID, which should be species specific most genes. Note not to map at higher than 97% ID because you'll get redundant hits.

```{bash, eval = F}
# Combine all of the output from the last few steps - this is what the database would look like without clustering!
# Note that we're adding the internal standard information in this step instead of processing as above.
./scripts/move_CDS_output.sh
```

Run the clustering - this runs a single job that may take a few days. Note that after 3 days, you get kicked off CHTC. Increase the number of threads or the amount of RAM if this happens. Mine finished in 2 days and 23 hours (phew!)
```{bash, eval = F}
condor_submit submits/06cd-hit.sub
```

We're going to take information from the clustering file to build a "dummy" gff file. Since each gene is its own "genome," they will start at 0 and go to the length of the gene. We want to retain the gene ID to use as the key for all of our .table.txt files of phylogeny and product info later. The 07nrdb_gff script took a day and a half. The 07.2nrdb_gff script took about 4 hours.

```{bash, eval = F}
# calculate max size of clusters to include in 07nrdb_gff.sh with this command (add 1):
# this reduces the amount of lines we need to grep through

sort -nrk1,1 /mnt/gluster/amlinz/nonredundant_database.fna.clstr  | head -1 | cut -f1
gzip /mnt/gluster/amlinz/nonredundant_database.fna.clstr
./scripts/split_fastaheaders.sh
# Mine is 997, I'll round up to 1000
# Send it over to squid, it's small enough to transfer and will be refernced by many jobs
mv /mnt/gluster/amlinz/nonredundant_database.fna.clstr.gz /squid/amlinz/

# Build the gff file in pieces
condor_submit submits/07nrdb_gff.sub

./scripts/cat_nrdbgff.sh

# Four lines in mine did not work for some reason. Fix with these lines on the submit server:
# Do NOT run if 07.2nrdb_gff reports no errors
gzip -d /mnt/gluster/amlinz/unprocessed-nrdb.gff.gz
gzip -d /squid/amlinz/nonredundant_database.fna.clstr.gz
grep "Cluster" /mnt/gluster/amlinz/unprocessed-nrdb.gff > ok.gff
grep -v "Cluster" /mnt/gluster/amlinz/unprocessed-nrdb.gff | awk {'print $1'} > notok.gff
maxsize=1000
touch endpoint.txt
cat notok.gff | while read line; do grep -B $maxsize $line /squid/amlinz/nonredundant_database.fna.clstr > splitfile.clstr; cluster=`grep "Cluster" splitfile.clstr | tail -1`; echo $cluster; length=`tail -1 splitfile.clstr | awk '{print $2}' | sed 's/[^0-9]*//g'`; echo $length >> endpoint.txt;done > clusters.txt
rows=$(wc -l notok.gff | awk '{print $1}')
yes "CDS" | head -n $rows > type.txt
yes "1" | head -n $rows > start.txt
yes "." | head -n $rows > info1.txt
yes "+" | head -n $rows > info2.txt
yes "0" | head -n $rows > info3.txt
yes "ID" | head -n $rows > ID.txt

paste -d "=" ID.txt notok.gff > tags.txt
paste notok.gff clusters.txt type.txt start.txt endpoint.txt info1.txt info2.txt info3.txt tags.txt > add2.gff
# The internal standard is one of the bad ones - fix in nano
cat ok.gff add2.gff > /mnt/gluster/amlinz/unprocessed-nrdb.gff
gzip /mnt/gluster/amlinz/unprocessed-nrdb.gff
gzip /squid/amlinz/nonredundant_database.fna.clstr
cp /mnt/gluster/amlinz/unprocessed-nrdb.gff.gz /squid/amlinz/unprocessed-nrdb.gff.gz

# Fix it up using genometools
condor_submit submits/07.2nrdb.gff.sub
```


move_CDS_output.sh
```{bash, eval = F}
#!/bin/bash

mv /home/amlinz/CDS*.fna /home/amlinz/CDS_fastas
cat /home/amlinz/CDS_fastas/* /home/amlinz/ref_MAGs_SAGs/fastas/pFN18A_DNA_transcript.fna > CDS_regions.fna
echo "pFN18A_DNA_transcript  internal standard internal standard internal standard" > internalstd.txt
cat /home/amlinz/*.table.txt internalstd.txt > CDS_regions_genekey.txt
gzip CDS_regions.fna
cp CDS_regions.fna.gz /mnt/gluster/amlinz/
cp CDS_regions_genekey.txt /mnt/gluster/amlinz/

```

06cd-hit.sub
```{bash, eval = F}
# 06cd-hit.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 06cd-hit_$(Cluster).log
error = 06cd-hit_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)

#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/06cd-hit.sh
#arguments = $(samplename)
output = 06cd-hit_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/cd-hit.tar.gz
#transfer_output_files =
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 12
request_memory = 36GB
request_disk = 20GB
#
# run one instance
queue

```

06cd-hit.sh
```{bash, eval = F}
#!/bin/bash
#Cluster coding regions to get nonredundant genes and make a dummy gff file to go with it

tar xvzf cd-hit.tar.gz

cp /mnt/gluster/amlinz/CDS_regions.fna.gz .
gzip -d CDS_regions.fna.gz

./cd-hit-v4.6.8-2017-0621/cd-hit-est -i CDS_regions.fna -o nonredundant_database.fna -c 0.97 -M 36000 -T 12 -d 50


grep ">" nonredundant_database.fna > fasta_headers.txt
#remove the carrot
sed -e 's/>//g' fasta_headers.txt > temp.txt && mv temp.txt fasta_headers.txt

gzip nonredundant_database.fna
mv nonredundant_database.fna.gz /mnt/gluster/amlinz
mv nonredundant_database.fna.clstr /mnt/gluster/amlinz
mv fasta_headers.txt /mnt/gluster/amlinz

rm *tar.gz
rm *fna
rm *clstr
rm *gff
rm *txt
rm -r cd-hit-v4.6.8-2017-0621

```

split_fastaheaders.sh
```{bash, eval = F}
#!/bin/bash
mkdir split_fastaheaders
split -l 1500 -a 4 -d /mnt/gluster/amlinz/fasta_headers.txt split_fastaheaders/fastaheaders

#1500 should aim for just under 10000 jobs
# Make a list of files to run
ls split_fastaheaders > splitfastaheaders.txt

# Move cluster file to squid for the next step
mv /mnt/gluster/amlinz/nonredundant_database.fna.clstr.gz /squid/amlinz/nonredundant_database.fna.clstr.gz

```

07nrdb_gff.sub
```{bash, eval = F}
# 07nrdb_gff.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 07nrdb_gff_$(Cluster).log
error = 07nrdb_gff_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (OpSysMajorVer == 6)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/07nrdb_gff.sh
output = 07nrdb_gff_$(Cluster).out
arguments=$(thing)
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT_OR_EVICT
transfer_input_files = /home/amlinz/split_fastaheaders/$(thing),http://proxy.chtc.wisc.edu/SQUID/amlinz/nonredundant_database.fna.clstr.gz
transfer_output_files = $(thing)-nrdb.gff
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 8GB
request_disk = 2GB
#
# run from list
queue thing from splitfastaheaders.txt


```

07nrdb_gff.sh
```{bash, eval = F}
#!/bin/bash
#Make a dummy gff file to go with the nonredundant database

gzip -d nonredundant_database.fna.clstr.gz
#Link cluster
#maxsize=$(sort -nrk1,1 /mnt/gluster/amlinz/nonredundant_database.fna.clstr  | head -1 | cut -f1)
#maxsize=$(($maxsize + 1))
maxsize=800
touch endpoint.txt
cat $1 | while read line; do grep -B $maxsize $line nonredundant_database.fna.clstr > splitfile.clstr; cluster=`grep "Cluster" splitfile.clstr | tail -1`; echo $cluster; length=`tail -1 splitfile.clstr | awk '{print $2}' | sed 's/[^0-9]*//g'`; echo $length >> endpoint.txt;done > clusters.txt

#already, now the good part. Make a couple of dummy columns and put the whole shebang together.
# I need:
# first line is version of gff
# genome name - something like "NR_database"
# source - cluster number
# type - CDS
# start - 1
# stop - my calculated endpoints
# strand and frame info - ., +, 0
# tags - use the fasta header as ID

rows=$(wc -l $1 | awk '{print $1}')
#yes "NR_gene_database" | head -n $rows > genome.txt
yes "CDS" | head -n $rows > type.txt
yes "1" | head -n $rows > start.txt
yes "." | head -n $rows > info1.txt
yes "+" | head -n $rows > info2.txt
yes "0" | head -n $rows > info3.txt
yes "ID" | head -n $rows > ID.txt

paste -d "=" ID.txt $1 > tags.txt
paste $1 clusters.txt type.txt start.txt endpoint.txt info1.txt info2.txt info3.txt tags.txt > $1-nrdb.gff

rm *txt
rm $1

```

cat_nrdbgff.sh
```{bash, eval = F}
#!/bin/bash
cat fastaheaders*-nrdb.gff > /mnt/gluster/amlinz/unprocessed-nrdb.gff
sed -i -e 's/ID=>/ID=/' /mnt/gluster/amlinz/unprocessed-nrdb.gff
gzip /mnt/gluster/amlinz/unprocessed-nrdb.gff

```

07.2nrdb.gff.sub
```{bash, eval = F}
# 07.2nrdb_gff.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 07.2nrdb_gff_$(Cluster).log
error = 07.2nrdb_gff_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/07.2nrdb_gff.sh
#arguments = $(samplename)
output = 07.2nrdb_gff_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = /home/amlinz/zipped/genometools.tar.gz,http://proxy.chtc.wisc.edu/SQUID/amlinz/unprocessed-nrdb.gff.gz
#transfer_output_files = 
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
request_cpus = 1
request_memory = 10GB
request_disk = 6GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue

```

07.2nrdb.gff.sh
```{bash, eval = F}
#!/bin/bash

tar xvzf genometools.tar.gz
export PATH=$(pwd)/genometools/bin:$PATH

gzip -d unprocessed-nrdb.gff.gz
echo '##gff-version 3' | cat - unprocessed-nrdb.gff > temp.gff
gt gff3 -sort yes -tidy -retainids -o sorted_database.gff temp.gff

echo "pFN18A_DNA_transcript     >Cluster X      CDS     1       917     .      +0       ID=pFN18A-DNA-transcript" > temp.gff
cat sorted_database.gff temp.gff > nonredundant_database.gff
sed -i 's/>//' nonredundant_database.gff

gzip nonredundant_database.gff
mv nonredundant_database.gff.gz /mnt/gluster/amlinz

rm *tar.gz
rm -r genometools
rm *gff

```

8. Your home folder probably looks like a war zone. Back up a copy of the non-redundant database fna and gff, and the CDS_regions_genekey.txt file. Delete all the log, out, and err files, as well as all intermediate files. You can probably delete the genome inputs, too, but be warned that uploading takes awhile if you realize something is wrong in the next step and need to rerun things.

##Mapping

####Goal of this analysis
Now that we've built a spiffy nonredundant database, we need to match our metatranscriptomic reads to that database. This step is called mapping. For now, we'll just figure out where each read matches best in the nonredundant database. Counting and linking that back to product and taxonomy information comes later.

####Approach
Because I want to do a competitive mapping (keep best hit only), I can't split up the database. Indexing is the most computationally intensive step, so I'll index once and save it to gluster, then copy that same index to all my mapping jobs.

Someone once told me that mapping is kind of a let down because you spend so much time getting your data ready to map, and then the mapping itself is pretty quick and painless. It's the same idea here.


0. Installing programs
We've already installed bbmap for its fastq splitting function. Now we'll just need samtools to convert between sam and bam output. I'm using version 1.3.1 downloaded from here: https://sourceforge.net/projects/samtools/files/samtools/

In an interactive session:

```{bash, eval = F}
tar xvfj samtools-1.3.1.tar.bz2
cd samtools-1.3.1
make
make prefix=../samtools install
cd ..
ls samtools
tar czvf samtools.tar.gz samtools/
ls
exit

#Move samtools to the zipped/ folder
mv samtools.tar.gz zipped/samtools.tar.gz
```



1. Build the index.  The issue is that the database is enormous. Splitting the files doesn't work as we want to perform competitive mapping (report best hit from entire database only). To solve this issue, I'm building the database index once, storing it in gluster, and then referencing all other mapping jobs to this index. This step took about 2 hours.

```{bash, eval = F}
condor_submit submits/08build_index.sub
```

08build_index.sub
```{bash, eval = F}
# 08build_index.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 08build_index_$(Cluster).log
error = 08build_index_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX")
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/08build_index.sh
output = 08build_index_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/BBMap_36.99.tar.gz
#transfer_output_files =
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory = 48GB
request_disk = 24GB
#
#
queue

```

08build_index.sh
```{bash, eval = F}
#!/bin/bash
#Build a re-usable mapping index
cp /mnt/gluster/amlinz/nonredundant_database.fna.gz .
gzip -d nonredundant_database.fna.gz
tr -d ' ' < nonredundant_database.fna > nonredundant_database_nospace.fna

#Unzip bbmap and build the index
tar -xvzf BBMap_36.99.tar.gz
bbmap/bbmap.sh ref=nonredundant_database_nospace.fna usemodulo=T -Xmx30g

# Make ref/ a tarball and move to gluster
tar czvf ref.tar.gz ref/

cp ref.tar.gz /mnt/gluster/amlinz/
rm ref.tar.gz
rm nonredundant_database.fna
rm -rf bbmap/

```

2. Run the mapping. I'm not splitting up the metatranscriptomes (even though I could) because they don't take very long to run, relatively speaking. This took me a day and a half to run. The smaller files finished in one hour and the large ones took that full time.

I chose 90%ID as my cutoff because I thought it gave me a good balance between not being strain/species specifici (which would be > 95%) and being fairly stringent. About 50% of reads mapped at this level, which is pretty awesome for metatranscriptomics. You can change the cutoff as you wish - lowering it will give you more mapped reads and annotations, but not classifications, while increasing it will give you information about specific populations, but fewer mapped reads. Just don't go above the clustering %ID of the nonredundant database (97% in this case) or the database will no longer be nonredundant.

```{bash, eval = F}
mkdir /mnt/gluster/amlinz/GEODES_mapping_results/
ls /mnt/gluster/amlinz/GEODES_nonrRNA > path2mappingfastqs.txt
condor_submit submits/09mapping.sub
```

09mapping.sub
```{bash, eval = F}
# 09mapping.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 09mapping_$(Cluster).log
error = 09mapping_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX")
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/09mapping.sh
arguments = $(samplename)
output = 09mapping_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/BBMap_36.99.tar.gz,zipped/samtools.tar.gz
#transfer_output_files =
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory =35GB
request_disk = 20GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue samplename from path2mappingfastqs.txt

```

09mapping.sh
```{bash, eval = F}
#!/bin/bash
#Map metatranscriptome reads to my pre-indexed database of reference genomes
#Transfer metaT from gluster
#Not splitting the metaTs anymore
cp /mnt/gluster/amlinz/GEODES_nonrRNA/$1 .
cp /mnt/gluster/amlinz/ref.tar.gz .

#Unzip program and database
tar -xvzf BBMap_36.99.tar.gz
tar -xvf samtools.tar.gz
tar -xvzf ref.tar.gz
gzip -d $1
name=$(basename $1 | cut -d'.' -f1)
sed -i '/^$/d' $name.fastq

#Run the mapping step
bbmap/bbmap.sh in=$name.fastq out=$name.90.mapped.sam minid=0.90 trd=T sam=1.3 threads=1 build=1 mappedonly=T -Xmx32g

# I want to store the output as bam. Use samtools to convert.
./samtools/bin/samtools view -b -S -o $name.90.mapped.bam $name.90.mapped.sam

#Copy bam file back to gluster
cp $name.90.mapped.bam /mnt/gluster/amlinz/GEODES_mapping_results/



#Clean up
rm -r bbmap
rm -r ref
rm *.bam
rm *.sam
rm *.fastq
rm *.gz

```

Your results are now stored in gluster. Check to make sure the right number of files ended up there and that there is something in the files. The error files should not be empty, for some reason the bbmap output ends up here. That's ok. You can glance through these to get an idea of what % of reads mapped and other helpful stats. 

Go ahead and clean up your home folder, deleting log, err, and out files. Now is a good time to back up a copy of the mapped.bam files in gluster.

##Read Counting

####Goal of this analysis
If you were to convert your compressed .mapped.bam files to their non-binary .sam versions, you'd see that the files contain the fastq sequences of all mapped reads, their mapping locations, and the quality of the match. That's great and all, but we just need a table of how many reads hit each gene in the nonredundant database.

####Approach
We'll use FeatureCounts to count mapped reads. There are lots of programs that do this, but FeatureCounts is the fastest and produces the same results as the more popular (and slower) HTSeq-count when you toggle the settings to match.


0. Installing programs

I'm using FeatureCounts from the subread package version 1.5.2, available here: http://bioinf.wehi.edu.au/subread-package/
This install is pretty straightforward - unzip, make, and zip it back up.

In an interactive session:
```{bash, eval = F}
tar zxvf subread-1.5.2-source.tar.gz
cd subread-1.5.2-source/src
make -f Makefile.Linux
tar czvf subreads.tar.gz subread-1.5.2-source
exit
#Move to zipped/ back in home directory
```

1. Run FeatureCounts. This should be an easy, fast run. The one issue I ran into was making sure that the program isn't truncating gene names. You'll also need the nonredundant database gff file - this is what tells the program where each gene is located. Copy it over from gluster to squid. I've specified that FeatureCounts should count genes as a hit if at least 75% of the read matches the gene. This program took about 3 hours.

```{bash, eval = F}
# Make a list of files to run
for file in /mnt/gluster/amlinz/GEODES_mapping_results/*; do sample=$(basename $file |cut -d'.' -f1); echo $sample;done > bamfiles.txt

cp /mnt/gluster/amlinz/nonredundant_database.gff.gz /squid/amlinz/

# Submit the counting job
condor_submit submits/10featurecounts.sub
```

10featurecounts.sub:
```{bash, eval = F}

# 10featurecounts.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 10featurecounts_$(Cluster).log
error = 10featurecounts_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/10featurecounts.sh
arguments = $(samplename)
output = 10featurecounts_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/subreads.tar.gz,http://proxy.chtc.wisc.edu/SQUID/amlinz/nonredundant_database.gff.gz
transfer_output_files = $(samplename).90.CDS.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 16GB
request_disk = 8GB
#
# Tell HTCondor to run every file in the provided list:
queue samplename from bamfiles.txt


```

10featurecounts.sh:
```{bash, eval = F}
#!/bin/bash
#Count mapped reads
cp /mnt/gluster/amlinz/GEODES_mapping_results/$1.90.mapped.bam .
gzip -d nonredundant_database.gff.gz

#Unzip programs
tar -xvzf subreads.tar.gz
#Pair reads
#Count reads
./subread-1.5.2-source/bin/featureCounts -t CDS -g ID --fracOverlap 0.75 -M --fraction --donotsort -a nonredundant_database.gff -o $1.90.CDS.txt $1.90.mapped.bam

#Clean up - don't delete the text file, that is being sent back to the submit node
rm *.tar.gz
rm -r subread-1.5.2-source
rm *bam
rm *gff
rm *.txt.summary

```

2. Make a table of the results. Each of the FeatureCounts results is a file per sample, so I need to compile those. While we're at it, we can also remove bad samples and genes that had no hits in any sample.

Approximately 20% of my samples flunked out - the list of which ones is in 03processing_labnotebook.Rmd. Most were from Trout Bog Day 2, which makes me suspect equipment failure.

```{bash, eval = F}
# An optional manual curation - delete results files of samples with poor amplification of the standard (< 10 reads)
# This saves computational time down the road, and hopefully there are not many.
grep "pFN18A" *.CDS.txt | awk '{print $1,$7}'
# Delete .CDS.txt files with less than 5 reads assigned to the standard

# This script combines all the remaining CDS.txt files into a single table, removes rows that sum to zero, and splits up the list of gene names for the next step.
# Make sure you change the output file name! I like to put the date in mine as well as the mapping % ID so that I know which iteration this table is from.
./scripts/maketable.sh

```

maketable.sh:
```{bash, eval = F}
#!/bin/bash
awk '{print $1}' GEODES001-nonrRNA.90.CDS.txt | tail -n +2 > rownames.txt
for file in *.CDS.txt;do awk '{print $7}' $file | tail -n +3 > temp.txt;sample=$(basename $file |cut -d'.' -f1);echo $sample | cat - temp.txt > temp2.txt && mv temp2.txt $file;done

files=$(echo *CDS.txt)
paste rownames.txt $files > GEODES_ID90_2018-03-01.txt

mkdir split_genes

#Remove rows that sum to zero
awk 'NR > 1{s=0; for (i=3;i<=NF;i++) s+=$i; if (s!=0)print}' GEODES_ID90_2018-03-01.txt > GEODES_ID90_2018-03-01.readcounts.txt
awk '{print $1}' GEODES_ID90_2018-03-01.readcounts.txt > genes.txt
split -l 1000 -a 4 -d genes.txt split_genes/genes

#1500 should aim for just under 10000 jobs
# Make a list of files to run - only doing a couple to test
ls split_genes > split_genes.txt

```

2. Get the genekey. We already made the base file, CDS_region_genekey.txt. But now that we know which genes were expressed, we can just pull those out and drastically reduce the size of the file. The maketable.sh script already made a list of genes to keep, in increments suitable for high throughput. We'll run each bit on a different execute node and combine the output at the end.

```{bash, eval = F}
# Copy genekey database over to squid
cp /mnt/gluster/amlinz/CDS_regions_genekey.txt.gz /squid/amlinz/

# Submit the jobs that search for genes to keep in the larger genekey
condor_submit submits/11grep_genes.sub
./scripts/cat_geneinfo.sh

# Split by lake
./scripts/split_by_lake.sh

# Split the genekey file by lake. Since there's not much overlap in gene expression between lakes
# Need to gzip the .readcounts.txt file to get it under the transfer file limit size
# Make sure to change the file names in 12genekey.sh and .sub
gzip *readcounts.txt
condor_submit submits/12genekey.sub

```

11grep_genes.sub:
```{bash, eval = F}
# 11grep_genes.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 11grep_genes_$(Cluster).log
error = 11grep_genes_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/11grep_genes.sh
output = 11grep_genes_$(Cluster).out
arguments = $(filepart)
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = http://proxy.chtc.wisc.edu/SQUID/amlinz/CDS_regions_genekey.txt.gz,split_genes/$(filepart)
transfer_output_files = $(filepart).gene.info.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 12GB
request_disk = 8GB
#
queue filepart from split_genes.txt

```

11grep_genes.sh:
```{bash, eval = F}
#!/bin/bash
gzip -d CDS_regions_genekey.txt.gz
while read line; do grep $line CDS_regions_genekey.txt; done < $1 > $1.gene.info.txt

rm $1
rm CDS_regions_genekey.txt

```

cat_geneinfo.sh:
```{bash, eval = F}

#!/bin/bash

cat *gene.info.txt > /mnt/gluster/amlinz/GEODES_metaG_genekey.txt

```

split_by_lake.sh:
```{bash, eval = F}
#!/bin/bash
awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35}' GEODES_ID90_2018-03-01.txt > Sparkling_ID90_2018-03-02.txt
head -1 Sparkling_ID90_2018-03-02.txt > colnames.txt
awk 'NR > 1{s=0; for (i=3;i<=NF;i++) s+=$i; if (s!=0)print}' Sparkling_ID90_2018-03-02.txt > temp.txt
cat colnames.txt temp.txt > Sparkling_ID90_2018-03-02.readcounts.txt


# Trout Bog (epilimnion) - GEODEs053-100, 110
awk '{print $1,$36,$37,$38,$39,$40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$50,$51,$52,$53,$54,$55,$56, $57}' GEODES_ID90_2018-03-01.txt > Trout_ID90_2018-03-02.txt
head -1 Trout_ID90_2018-03-02.txt > colnames.txt
awk 'NR > 1{s=0; for (i=3;i<=NF;i++) s+=$i; if (s!=0)print}' Trout_ID90_2018-03-02.txt > temp.txt
cat colnames.txt temp.txt > Trout_ID90_2018-03-02.readcounts.txt



# Mendota - GEODES113-164
awk '{print $1,$58,$59,$60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$80,$81,$82,$83,$84,$85,$86,$87,$88}' GEODES_ID90_2018-03-01.txt > Mendota_ID90_2018-03-02.txt
head -1 Mendota_ID90_2018-03-02.txt > colnames.txt
awk 'NR > 1{s=0; for (i=3;i<=NF;i++) s+=$i; if (s!=0)print}' Mendota_ID90_2018-03-02.txt > temp.txt
cat colnames.txt temp.txt > Mendota_ID90_2018-03-02.readcounts.txt
```

12genekey.sub
```{bash, eval = F}

# 12genekey.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 12genekey_$(Cluster).log
error = 12genekey_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/12genekey.sh
output = 12genekey_$(Cluster).out
#arguments = $(filepart)
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = Mendota_ID90_2018-03-02.readcounts.txt.gz,Trout_ID90_2018-03-02.readcounts.txt.gz,Sparkling_ID90_2018-03-02.readcounts.txt.gz,scripts/genekey.py,zipped/python.tar.gz
#transfer_output_files =
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 8GB
request_disk = 4GB
#
queue

```

12genekey.sh
```{bash, eval = F}

#!/bin/bash

gzip -d *readcounts.txt.gz
cp /mnt/gluster/amlinz/GEODES_ID90_genekey.txt .

tar xzf python.tar.gz
export PATH=$(pwd)/python/bin:$(pwd)/samtools/bin:$PATH
export HOME=$(pwd)/home
chmod +x genekey.py

python genekey.py Mendota_ID90_2018-03-02.readcounts.txt Mendota_ID90_genekey.csv
python genekey.py Trout_ID90_2018-03-02.readcounts.txt Trout_ID90_genekey.csv
python genekey.py Sparkling_ID90_2018-03-02.readcounts.txt Sparkling_ID90_genekey.csv

cp *csv /mnt/gluster/amlinz

rm *txt
rm *csv
rm *py
rm python.tar.gz
rm -rf python/
rm -rf home/

```

#Mapping Metagenomes

###Goal

We microbial ecologists look at DNA a lot. It's often considered a proxy for abundance. One of the question we ask using metatranscriptomes is how an organism's level of expression compares to its abundance, but first we need to know how the metagenomes map to the same database we used for the metatranscriptomes.

###Approach

Pretty straightforward - a metagenome looks a lot like a metatranscriptome from a computer's point of view, and the point of this analysis is to use the same reference database, so we can use a lot of the same code from the metatranscriptome mapping. The main difference is that the metagenomes are prohibitibely huge (~80GB), so I downsample them. Otherwise, we'll just be modifying 09mapping - 11grepgenes to refer to metagenomes instead of metatranscriptomes.

0. Installs

None! You already installed everything for mapping metatranscriptomes.

1. Sample metagenomes. This is a commonly used technique when working with really huge data. You do lose some accuracy by doing this, but since the purpose of this analysis is to compare to expression data at roughly the phylum level (and because I'd like to get data back within the next month), I'm ok with that. BBMap comes with a nice function for downsampling fastq files, which is what we use here. I'm sampling 10% reads, which puts the metagenomes roughly in the size range of the metatranscriptomes.

Note the absolutely ridiculous disk space requirement in the submit script. The job itself only takes a couple hours, but waiting to match to an execute node with over 100GB of free space for you to use can take awhile.

```{bash, eval = F}
# put metagenome names in metaG_samples.txt
condor_submit submits/13sample_metaGs.sub

```

13sample_metaGs.sub
```{bash, eval = F}
# 13sample_metaG.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 13sample_metaG_$(Cluster).log
error = 13sample_metaG_$(Cluster)_$(Process).err
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/13sample_metaG.sh
arguments = $(sample)
output = 13sample_metaG_$(Cluster).out
#
# No files to transfer, since it's going to interact with Gluster instead of the submit node
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/BBMap_36.99.tar.gz
transfer_output_files =
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory = 16 GB
request_disk = 108 GB
#
# Submit jobs
queue sample from metaG_samples.txt

```

13sample_metaGs.sh
```{bash, eval = F}
#!/bin/bash
#Downsample metagenomes to 10 percent
#Transfer metaG from gluster
cp /mnt/gluster/amlinz/GEODES_metagenomes/$1-metaG.fastq.gz .

#Unzip program
tar -xvzf BBMap_36.99.tar.gz
gzip -d $1-metaG.fastq.gz

#BBmap to sample
bbmap/reformat.sh in=$1-metaG.fastq out=$1-sampled.fastq samplerate=0.1

gzip $1-sampled.fastq

#Copy file back to gluster
cp $1-sampled.fastq.gz /mnt/gluster/amlinz/downsampled_metagenomes/

#Clean up
rm -r bbmap
rm *.fastq
rm *.gz

```

2. Mapping. Nothing new here - all we're doing is changing the scripts to reference our downsampled metagenomes instead of the metatranscriptomes. As such, I'm renaming the scripts above with a ".2" since they're basically the same thing. It's ok to overwrite intermediate files like path2mappingfastqs.txt, since you don't need them downstream.

```{bash, eval = F}
# No need to rerun 08build_index, since you're using the same reference database
mkdir /mnt/gluster/amlinz/GEODES_metaG_mapping_results/
ls /mnt/gluster/amlinz/downsampled_metagenomes > path2mappingfastqs.txt
condor_submit submits/09.2mapping.sub
```

09.2mapping.sub
```{bash, eval = F}
# 09.2mapping.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 09.2mapping_$(Cluster).log
error = 09.2mapping_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/09.2mapping.sh
arguments = $(samplename)
output = 09.2mapping_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/BBMap_36.99.tar.gz,zipped/samtools.tar.gz
#transfer_output_files =
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
request_cpus = 1
request_memory =36GB
request_disk = 20GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue samplename from path2mappingfastqs.txt

```

09.2mapping.sh
```{bash, eval = F}
#!/bin/bash
#Map metagenome reads to my pre-indexed database of reference genomes
#Transfer metaG from gluster
#Not splitting the metaTs anymore
cp /mnt/gluster/amlinz/downsampled_metagenomes/$1 .
cp /mnt/gluster/amlinz/ref.tar.gz .

#Unzip program and database
tar -xvzf BBMap_36.99.tar.gz
tar -xvf samtools.tar.gz
tar -xvzf ref.tar.gz
gzip -d $1
name=$(basename $1 | cut -d'.' -f1)
sed -i '/^$/d' $name.fastq

#Run the mapping step
bbmap/bbmap.sh in=$name.fastq out=$name.90.mapped.sam minid=0.90 trd=T sam=1.3 threads=1 build=1 mappedonly=T -Xmx32g

# I want to store the output as bam. Use samtools to convert.
./samtools/bin/samtools view -b -S -o $name.90.mapped.bam $name.90.mapped.sam

#Copy bam file back to gluster
cp $name.90.mapped.bam /mnt/gluster/amlinz/GEODES_metaG_mapping_results/


#Clean up
rm -r bbmap
rm -r ref
rm *.bam
rm *.sam
rm *.fastq
rm *.gz

```

3. Count reads. Same idea as above - the 10.2 script is just script #10 referencing mapped metagenomes instead of metatranscriptomes.

```{bash, eval = F}
for file in /mnt/gluster/amlinz/GEODES_metaG_mapping_results/*; do sample=$(basename $file |cut -d'.' -f1); echo $sample;done > bamfiles.txt

```

10.2featurecounts.sub
```{bash, eval =F}

# 10.2featurecounts.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 10.2featurecounts_$(Cluster).log
error = 10.2featurecounts_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/10.2featurecounts.sh
arguments = $(samplename)
output = 10.2featurecounts_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/subreads.tar.gz,http://proxy.chtc.wisc.edu/SQUID/amlinz/nonredundant_database.gff.gz
transfer_output_files = $(samplename).90.CDS.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 16GB
request_disk = 8GB
#
# Tell HTCondor to run every file in the provided list:
queue samplename from bamfiles.txt

```

10.2featurecounts.sh
```{bash, eval = F}
#!/bin/bash
#Count mapped reads
cp /mnt/gluster/amlinz/GEODES_metaG_mapping_results/$1.90.mapped.bam .
gzip -d nonredundant_database.gff.gz

#Unzip programs
tar -xvzf subreads.tar.gz
#Pair reads
#Count reads
./subread-1.5.2-source/bin/featureCounts -t CDS -g ID --fracOverlap 0.75 -M --fraction --donotsort -a nonredundant_database.gff -o $1.90.CDS.txt $1.90.mapped.bam

#Clean up - don't delete the text file, that is being sent back to the submit node
rm *.tar.gz
rm -r subread-1.5.2-source
rm *bam
rm *gff
rm *.txt.summary

```

4. Put the results in table form.

```{bash, eval = F}
./scripts/maketable.sh #Modify names for metagenomes
gzip *readcounts.txt
```

maketable.sh
```{bash, eval = F}
#!/bin/bash
awk '{print $1}' GEODES005-sampled.90.CDS.txt | tail -n +2 > rownames.txt
for file in *.CDS.txt;do awk '{print $7}' $file | tail -n +3 > temp.txt;sample=$(basename $file |cut -d'.' -f1);echo $sample | cat - temp.txt > temp2.txt && mv temp2.txt $file;done

files=$(echo *CDS.txt)
paste rownames.txt $files > GEODES_metaG_ID90_2018-03-10.txt

mkdir split_genes

#Remove rows that sum to zero
awk 'NR > 1{s=0; for (i=3;i<=NF;i++) s+=$i; if (s!=0)print}' GEODES_metaG_ID90_2018-03-10.txt > GEODES_metaG_ID90_2018-03-10.readcounts.txt
awk '{print $1}' GEODES_metaG_ID90_2018-03-10.readcounts.txt > genes.txt
split -l 1000 -a 4 -d genes.txt split_genes/genes

#Add column name
head -1 GEODES_metaG_ID90_2018-03-10.txt > colnames.txt
cat colnames.txt GEODES_metaG_ID90_2018-03-10.readcounts.txt > temp.txt
mv temp.txt GEODES_metaG_ID90_2018-03-10.readcounts.txt

#1500 should aim for just under 10000 jobs
# Make a list of files to run - only doing a couple to test
ls split_genes > split_genes.txt


```

5. Get gene info. Since gene split names are the same, no need to modify 11grepgenes.
```{bash, eval = F}
condor_submit submits/11grep_genes.sub
./scripts/cat_geneinfo.sh
```

cat_geneinfo.sh
```{bash, eval = F}
#!/bin/bash

cat *gene.info.txt > /mnt/gluster/amlinz/GEODES_metaG_genekey.txt

```

Since you're not splitting by lake for the metagenomes (there are only a couple), you're done! Download the genekey and readcounts table, make sure to reclassify the gene taxonomy based on bin taxonomy (see below), and compare to counts of metatranscriptomes in the summary_stats script.

#Binning

####Goal
Part of the point of the reference database is to assign taxonomy to metatranscriptomic reads, which means those classifications will only be as good as the reference database. Earlier, we classified contigs in the metagenome assemblies based on phylodist files from JGI that match each gene to something in the IMG database. But contig classifications are never that good, since there's only so much DNA. We can get better classifications by binning the contigs into genomes and classifying the genomes instead. Bin classifications can be reassigned in the genekey files post-mapping.

####Approach
There are lots of programs for binning. The general idea is to use a combination of genome properties such as kmer frequency and GC content and read coverage from the metagenomes. I don't have many metagenomes, so the read coverage isn't all that helpful, but it's better than nothing. I chose the program MaxBin because it has been shown to work well on high complexity datasets.

0. Installs

I'm using the program MaxBin. I've downloaded version 2.2.4 from https://downloads.jbei.org/data/microbial_communities/MaxBin/MaxBin.html

I'm following the installation instructions here: https://downloads.jbei.org/data/microbial_communities/MaxBin/README.txt

In an interactive session:
```{bash, eval = F}
tar xvzf MaxBin-2.2.4.tar.gz
cd MaxBin-2.2.4
cd src
make
cd ..
./autobuild_auxiliary

```

At the beginning of the binning script, you'll need to set the PATH for the auxiliary programs MaxBin uses.

1. We've already downsampled and mapped the metagenomes, so no need to do that again. But we can further reduce the computational power needed by removing tiny contigs that aren't likely to bin anyway (or add much information even if they do bin). My cutoff is 1000 bp long, which is about one gene.

I have my metagenome assembly files wrapped up in tarballs called GEODES<metagenome number>.datafiles2.tar.gz. It has extra stuff in it I was using for testing. Because it's on squid, change the submit file for each one and submit separately. Don't worry, each one doesn't take long.

```{bash, eval = F}
mkdir /mnt/gluster/amlinz/filtered_assemblies
condor_submit submits/14contig_filter.sub
```

14contig_filter.sub:
```{bash, eval = F}
# 14contig_filter.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 14contig_filter_$(Cluster).log
error = 14contig_filter_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX") && (Target.HasGluster == true)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/14contig_filter.sh
arguments = $(samplename)
output = 14contig_filter_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/BBMap_36.99.tar.gz,http://proxy.chtc.wisc.edu/SQUID/amlinz/GEODES005.datafiles2.tar.gz

#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.
# Requirements = (Target.HasGluster == true)
request_cpus = 1
request_memory = 16GB
request_disk = 8GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue samplename from contigs.txt

```

14contig_filter.sh:
```{bash, eval = F}
#!/bin/bash
tar -xvzf BBMap_36.99.tar.gz

tar -xvzf $1.datafiles2.tar.gz
gzip -d $1.assembled.fna.gz

./bbmap/reformat.sh in=$1.assembled.fna out=$1-filtered.assembled.fna minlength=1000

gzip $1-filtered.assembled.fna

cp $1-filtered.assembled.fna.gz /mnt/gluster/amlinz/filtered_assemblies/

rm *gz
rm *fna
rm *txt
rm *product_names
rm -r bbmap

```

2.Bin time! 

```{bash, eval = F}
condor_submit submits/15binning.sub
```

15binning.sub
```{bash, eval = F}
#15binning.sub
#
universe = vanilla
# Name the log file:
log = 15binning.log

# Name the files where standard output and error should be saved:
output = 15binning.out
error = 15binning.err

executable = executables/15binning.sh

# If you wish to compile code, you'll need the below lines.
#  Otherwise, LEAVE THEM OUT if you just want to interactively test!
requirements = ( OpSysMajorVer == 7 ) && ( Target.HasGluster == true )
arguments = $(metaG)

# Indicate all files that need to go into the interactive job session,
#  including any tar files that you prepared:
transfer_input_files = MaxBin.tar.gz

# It's still important to request enough computing resources. The below
#  values are a good starting point, but consider your file sizes for an
#  estimate of "disk" and use any other information you might have
#  for "memory" and/or "cpus".

request_cpus = 1
request_memory = 24GB
request_disk = 16GB

queue metaG from metaG_samples.txt
```

15binning.sh
```{bash, eval = F}
#!/bin/bash
# Test binning on one metagenome assembly
# Both the assembled data and the reads have already been slimmed down
tar xvzf MaxBin.tar.gz

export PATH=$(pwd)/MaxBin-2.2.4/auxiliary/FragGeneScan1.30:$PATH
export PATH=$(pwd)/MaxBin-2.2.4/auxiliary/bowtie2-2.2.3:$PATH
export PATH=$(pwd)/MaxBin-2.2.4/auxiliary/hmmer-3.1b1/src:$PATH
export PATH=$(pwd)/MaxBin-2.2.4/auxiliary/idba-1.1.1/bin:$PATH

cp /mnt/gluster/amlinz/filtered_assemblies/$1-filtered.assembled.fna.gz .
cp /mnt/gluster/amlinz/downsampled_metagenomes/$1-sampled.fastq.gz .

gzip -d $1-filtered.assembled.fna.gz
gzip -d $1-sampled.fastq.gz

./MaxBin-2.2.4/run_MaxBin.pl -contig $1-filtered.assembled.fna -out $1-binned -reads $1-sampled.fastq

mkdir $1-binning
mv $1-binned* $1-binning/
tar cvzf $1-binning.tar.gz $1-binning/
mv $1-binning.tar.gz /mnt/gluster/amlinz/

rm *assembled.fna
rm *fastq

```

3. We need a bit more info about the quality of the bins. Run CheckM to get completeness and contamination estimates. 

Remember when I said installing programs is hard, so I got a labmate to make a docker image for me? This is it. If you don't have Docker installed on your machine, you're on your own.

```{bash, eval = F}
# Put all the bins from all the metagenomes in a single folder and list.
# The bins are output as .fasta, but CheckM only accepts .fna, so change the file extensions here
./move_bins.sh

condor_submit submits/16checkm.sub

#Concatenate results
./checkm_results.sh
```

move_bins.sh
```{bash, eval = F}
#!/bin/bash

while read line; do tar xvzf /mnt/gluster/amlinz/$line-binning.tar.gz;
       for file in $line-binning/*fasta; do
               name=$(basename "$file" .fasta);
               mv $file metaG_bins/$name.fna;
               done;
       rm -r $line-binning;
       done < metaG_samples.txt

for file in metaG_bins/*; do
        name=$(basename "$file" .fna);
        echo $name;
        done > bins_to_classify.txt

head -3 bins_to_classify.txt > testbins_to_classify.txt

```

16checkm.sub
```{bash, eval = F}
# 16checkm.sub
#
#
# Specify the HTCondor Universe
universe = docker
docker_image = sstevens/checkm:latest

log = 16checkm_$(Cluster).log
error = 16checkm_$(Cluster)_$(Process).err
requirements = (OpSysMajorVer == 7)
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = executables/16checkm.sh
arguments = $(bin)
output = 16checkm_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = metaG_bins/$(bin).fna
transfer_output_files = $(bin)-contigs.txt,$(bin)-checkm.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 40GB
request_disk = 12GB
#
# Tell HTCondor to run every fastq file in the provided list:
queue bin from bins_to_classify.txt

```

16checkm.sh
```{bash, eval = F}

#!/bin/bash

mkdir input
mv $1.fna input/

checkm lineage_wf input output

grep ">" input/$1.fna > contigs.txt
sed -i 's/>//g' contigs.txt
while read line; do
        echo $line $1;
        done < contigs.txt > $1-contigs.txt

tax=$(awk -F', ' '{for(i=1;i<=NF;i++){if ($i ~ /marker lineage/){print $i}}}' output/storage/bin_stats_ext.tsv | awk -F': ' '{print $2}')
length=$(awk -F', ' '{for(i=1;i<=NF;i++){if ($i ~ /Genome size/){print $i}}}' output/storage/bin_stats_ext.tsv | awk -F': ' '{print $2}')
complete=$(awk -F', ' '{for(i=1;i<=NF;i++){if ($i ~ /Completeness/){print $i}}}' output/storage/bin_stats_ext.tsv | awk -F': ' '{print $2}')
contamination=$(awk -F', ' '{for(i=1;i<=NF;i++){if ($i ~ /Contamination/){print $i}}}' output/storage/bin_stats_ext.tsv | awk -F': ' '{print $2}')

echo $1 $tax $length $complete $contamination > $1-checkm.txt

rm -r input/
rm -r output/

```

checkm_results.sh
```{bash, eval = F}
#!/bin/bash

cat *-contigs.txt > GEODES_binned_contigs.txt
echo -e "bin\ttaxonomy\tsize\tcompleteness\tcontamination" | cat - *-checkm.txt > GEODES_checkm_results.txt

```

4. One last thing we need to do - classification. You'll notice that CheckM spits out classifications, but we think we can do better using those Phylodist files again. And once again, I'm using one of Sarah's Python scripts to combine classifications. This script is very similar to the one used previously for contigs, but includes contigs assigned to the same bin. It also pulls out marker COGs (from the Phylosift list) instead of using all genes.

Credit to Sarah Stevens for these scripts!

The steps in the process are:
- assembly.gff + bin.contig.list > bin.gff
- bin.gff + assembly.phylodist > bin.phylodist
- bin.gff + assembly.COG > bin.COG
- bin.COG + bin.phylodist > bin.markerCOG.phylodist
- bin.markerCOG.phylodist > classification

Once this is done, we'll replace contig level classifications with bin classifications in the genekeys in R.

```{bash, eval = F}
# Using the same bins list for input as CheckM
condor_submit submits/17classify_bins.sub

# Concatenate output
cat *.perc70.minhit3.classonly.txt > bin_classifications.txt
```

17classify_bins.sub
```{bash, eval = F}
# 17classify_bins.sub
#
#
# Specify the HTCondor Universe
universe = vanilla
log = 17classify_bins_$(Cluster).log
error = 17classify_bins_$(Cluster)_$(Process).err
requirements = (OpSys == "LINUX")
#
# Specify your executable, arguments, and a file for HTCondor to store standard
#  output.
executable = /home/amlinz/executables/17classify_bins.sh
arguments = $(bin)
output = 17classify_bins_$(Cluster).out
#
# Specify that HTCondor should transfer files to and from the
#  computer where each job runs.
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = zipped/python.tar.gz
transfer_output_files = $(contigs).contig.classification.perc70.minhit3.txt
#
# Tell HTCondor what amount of compute resources
#  each job will need on the computer where it runs.

request_cpus = 1
request_memory = 16GB
request_disk = 16GB
#
# run from list
queue bin from bins_to_classify.txt

```

17classify_bins.sh
```{bash, eval = F}
#!/bin/bash

tar xvzf python.tar.gz
#Update the path variable
mkdir home
export PATH=$(pwd)/python/bin:$(pwd)/samtools/bin:$(pwd)/bwa:$PATH
export HOME=$(pwd)/home

# Unzip assembly data files
tar xvzf for_bin_classification.tar.gz

# Make all scripts executable
chmod +x *.sh
chmod +x *.py

# Make list of contigs
grep '>' $1.fna > $1.contigs

# Make gff file
./makeBinGFF.sh $1.contigs for_bin_classification/

# Make phylodist file
python makeBinPhylodist.py $1.gff for_bin_classification

# Make COG file
python makeBinCOGS.py $1.gff for_bin_classification

# Filter COGs to include only phylogeny marker genes
python filterPhyloCOGs.py $1.cog.txt

# Get the consensus phylogeny
python classifyWphylodistWcutoffs.py $1.phylodist.subphylocog.txt

# Simplify output name
mv *classonly.txt $1.perc70.minhit3.classonly.txt

# Clean up
rm *.tar.gz
rm *.py
rm *.sh
rm *.tsv
rm *.gff
rm *.fna
rm *.fna.contigs
rm *cog.txt
rm *phylodist.txt
rm *minhit3.txt
rm -r for_bin_classification/
rm -rf python/
rm -r home/
```

makeBinGFF.sh
```{bash, eval = F}
#!/bin/bash

# This program makes a gff file for the individual bin from the assembly gff
# Usage: makeBinGFF contiglistFile path2assemblies

# Read in filename
filename=$1
# Get path to assemblies
assemPath=$2
# Put together name for assembly gff file
gffFilename=`echo "$filename" | cut -f1 -d- `
#gffFilename=${gffFilename##*/}
# Make bin GFF file name
gffOut="${filename%.contigs}".gff

# Grep each line of the filename (minus first character) from the gff file 
#    into new bin gff file
while read line
do
grep "${line:1:${#line}}" $assemPath/$gffFilename.assembled.gff >> $gffOut
done < $filename
```

makeBinPhylodist.py
```{python, eval=F, python.reticulate = F}
# coding: utf-8

"""makeBinPhylodist.py : make phyldist file for each bin"""

__author__ = "Sarah Stevens"
__email__ = "sstevens2@wisc.edu"

import pandas as pd, sys

def usage():
	print("Usage: makeBinPhylodist.py  gffFile path2assemblies")

if len(sys.argv) != 3:
	usage()
	sys.exit(2)

gffname=sys.argv[1]
assemName=gffname.split('-')[0]
path2assem=sys.argv[2]
phylodistname=path2assem+'/'+assemName+'.assembled.phylodist'

gff=pd.read_table(gffname, header=None, names=['seqname','source','features','start','end','score','strand','frame','attribute'])
#pulling out the locus tag to its own column
gff['locus_tag']=gff['attribute'].str.split('locus_tag=').str.get(1).str.slice(start=0,stop=-1)
phylodist=pd.read_table(phylodistname, header=None, names=['seq_id','homolog_gene_oid','homolog_taxon_oid','percent_identity','lineage'])
## Merging and writing out to file, did inner instead of left since some of the genes don't have a hit in the phylodist file
gff[['locus_tag']].merge(phylodist, how='inner', left_on='locus_tag', right_on='seq_id').to_csv(gffname.split('.gff')[0]+'.phylodist.txt',sep='\t', index=False)
```

makeBinCOGS.py
```{python, eval = F, python.reticulate = F}
# coding: utf-8

"""makeBinPhylodist.py : make cog file for each bin"""

__author__ = "Sarah Stevens"
__email__ = "sstevens2@wisc.edu"

import pandas as pd, sys

def usage():
	print("Usage: makeBinCOGs.py  gffFile path2assemblies")

if len(sys.argv) != 3:
	usage()
	sys.exit(2)

gffname=sys.argv[1]
assemName=gffname.split('-')[0]
path2assem=sys.argv[2]
cogname=path2assem+'/'+assemName+'.assembled.COG'

gff=pd.read_table(gffname, header=None, names=['seqname','source','features','start','end','score','strand','frame','attribute'])
#pulling out the locus tag to its own column
gff['locus_tag']=gff['attribute'].str.split('locus_tag=').str.get(1).str.slice(start=0,stop=-1)
cog=pd.read_table(cogname, header=None, names=['gene_id','cog_id','percent_identity','align_length','query_start','query_end','subj_start','subj_end','evalue','bit_score'])
## Merging and writing out to file, did inner instead of left since some of the genes don't have a hit in the cog file
gff[['locus_tag']].merge(cog, how='inner', left_on='locus_tag', right_on='gene_id').to_csv(gffname.split('.gff')[0]+'.cog.txt',sep='\t', index=False)
```

filterPhyloCOGs.py
```{python, eval = F, python.reticulate = F}
"""makeBinPhylodist.py : make cog file for each bin, requires matching names for COG file and phylodist files, preferably made with makeBinXXX.py scripts"""

__author__ = "Sarah Stevens"
__email__ = "sstevens2@wisc.edu"

import pandas as pd, sys

def usage():
	print("Usage: filterPhyloCOGs.py  COGsFile")

if len(sys.argv) != 2:
	usage()
	sys.exit(2)

cogname=sys.argv[1]
prefix=cogname.split('.cog.txt')[0]
phyloname=prefix+'.phylodist.txt'

matchup=pd.read_table('Phylosift2COGs.tsv',header=0) # hard coded in path2file, add as argument?


cogs=pd.read_table(cogname,header=0)
phylodist=pd.read_table(phyloname,header=0)
phylocogs=cogs[cogs.cog_id.isin(matchup.COG_num)]
phylocogs.to_csv(prefix+'.phylocog.txt',sep='\t', index=False)

phylodist[phylodist.locus_tag.isin(phylocogs.locus_tag)].to_csv(prefix+'.phylodist.subphylocog.txt',sep='\t', index=False)

```

classifyWphylodistWcutoffs.py
```{python, eval = F, python.reticulate = F}
import pandas as pd, sys, os

"""classifyWPhylodist.py  for each taxonomic level takes the classificaiton with the most hits,
	removes any not matching hits for the next leve, also returns the number and avg pid for those hits"""

__author__ = "Sarah Stevens"
__email__ = "sstevens2@wisc.edu"

def usage():
	print("Usage: classifyWPhylodistWcutoffs.py  phylodistFile")

if len(sys.argv) != 2:
	usage()
	sys.exit(2)

# Read in args
inname=sys.argv[1]
phylodist = pd.read_table(inname)
perc_co = .70
hit_min = 3
	

# Setting up output
outname=os.path.splitext(inname)[0]+'.perc70.minhit3.txt'
outname2=os.path.splitext(inname)[0]+'.perc70.minhit3.classonly.txt' # output file without the numbers in it
output=open(outname,'w')
output2=open(outname2,'w')
output.write(inname+'\t')
output2.write(inname+'\t')
if phylodist.empty: # if there are no hits in phylodist file
	print('Phylodist empty!  This maybe because it was subsetted into phylocogs and there were none.')
	output.write('NO CLASSIFICATION BASED ON GIVEN PHYLODIST\n')
	output2.write('NO CLASSIFICATION BASED ON GIVEN PHYLODIST\n')
	sys.exit(0)

phylodist['contig']=phylodist['locus_tag'].str[:17]
taxon_ranks=['Kingdom','Phylum','Class','Order','Family','Genus','Species','Taxon_name']
phylodist[taxon_ranks]=phylodist['lineage'].apply(lambda x: pd.Series(x.split(';')))
totGenes=len(phylodist)
genome_classification=list()


for rank in taxon_ranks:
	# Getting taxon, at that level, hit the most and the number of hits
	counts=phylodist.groupby(rank).size()
	max_ct_value=counts.max()
	perc=phylodist.groupby(rank).size()/float(totGenes) # percent of times each classification (added float for python2)
	max_pc_value=perc.max() # number of percentage the classification with the most hits had
	max_pc_taxon=perc.idxmax(axis=1) # classificaiton hit the most at this rank
	averages=phylodist.groupby(rank).mean().reset_index()[[rank,'percent_identity']] #getting average pid for best classifcation
	max_pc_avg=averages.loc[averages[rank]==max_pc_taxon, 'percent_identity'].iloc[0]
	result=(max_pc_taxon, round(max_pc_value, 2), round(max_pc_avg, 2), max_ct_value)
	genome_classification.append(result)
	rank_co_dict = {'Kingdom':.20,'Phylum':.45,'Class':.49,'Order':.53,'Family':.61,'Genus':.70,'Species':.90,'Taxon_name':.97}
	rank_co = rank_co_dict[rank]
	if (result[0]>.70 and result[3]>hit_min and result[1]>rank_co):
		output.write('{}({},{},{});'.format(result[0],result[1],result[2],result[3]))
		output2.write(result[0]+';')
	else:
		if rank == 'Kingdom':
			if result[3]<=hit_min:
				output.write('NO CLASSIFICATION DUE TO FEW HITS IN PHYLODIST')
				output2.write('NO CLASSIFICATION DUE TO FEW HITS IN PHYLODIST')
			else: 
				output.write('NO CLASSIFICATION DUE TO LOW PERCENT MATCHING')
				output2.write('NO CLASSIFICATION DUE TO LOW PERCENT MATCHING')
		output.write('\n')
		output2.write('\n')
		output.close()
		output2.close()
		sys.exit(0)
	phylodist=phylodist[phylodist[rank]==max_pc_taxon] # removing any hits which don't match the classification at this level

output.write('\n')
output.close()
output2.write('\n')
output2.close()

```

#R processing

####Goal

Congratulations, you now have a very manageable dataset! There are 6 main files you should have downloaded to a local computer for processing in R - the tables of readcounts for each lake, and the tables of information about the expressed genes in each lake. You'll also need the bin classifications for each lake. THIS IS THE PART WHERE WE GET RESULTS!!!

####Approach

A couple steps need to happen here. We need to:
- Add the bin classifications to the gene keys
- Normalize reads to transcripts per liter using the internal standard
- Aggregate reads by phylum and compare to the metagenomes
- Run a fourier transformation and cluster genes using weighted gene correlation network analysis
- Plot the results and get the gene information for each cluster

Each script runs independently in R. They can be sourced or run directly in the command prompt. The packages needed for each script are found at the top - they can be installed using the install.packages() command. These tables are still fairly hefty for R, so run one lake at a time to save RAM if needed.

add_bin_classifications.R
```{r eval = F}
# Update gene key files with classifications from binning

# Gene keys
mendota_key <- read.csv("D:/geodes_data_tables/Mendota_ID90_genekey.csv", header = T)
spark_key <- read.csv("D:/geodes_data_tables/Sparkling_ID90_genekey.csv", header = T)
trout_key <- read.csv("D:/geodes_data_tables/Trout_ID90_genekey.csv", header = T)
# Binning results
bins <- read.csv("D:/geodes_data_tables/GEODES_bin_data.csv", header = T)
contigs <- read.table("D:/geodes_data_tables/GEODES_binned_contigs.txt")

# Keep only good bins

bins <- bins[which(bins$completeness > 30 & bins$contamination < 10), ]
keep <- match(contigs$V2, bins$bin)
contigs <- contigs[which(is.na(keep) == F), ]

# Replace in lake keys
mendota_key$Taxonomy <- as.character(mendota_key$Taxonomy)
search <- match(mendota_key$Genome, as.character(contigs$V1))
where_in_key <- which(is.na(search) == F)
where_in_contigs <- search[where_in_key]
matching_bins <- contigs$V2[where_in_contigs]
taxonomy_add <- as.character(bins$phylodist_taxonomy[match(matching_bins, bins$bin)])
mendota_key$Taxonomy[where_in_key] <- taxonomy_add

write.csv(mendota_key, "D:/geodes_data_tables/Mendota_ID90_genekey_reclassified_2018-03-03.csv", row.names = F)

spark_key$Taxonomy <- as.character(spark_key$Taxonomy)
search <- match(spark_key$Genome, as.character(contigs$V1))
where_in_key <- which(is.na(search) == F)
where_in_contigs <- search[where_in_key]
matching_bins <- contigs$V2[where_in_contigs]
taxonomy_add <- as.character(bins$phylodist_taxonomy[match(matching_bins, bins$bin)])
spark_key$Taxonomy[where_in_key] <- taxonomy_add

write.csv(spark_key, "D:/geodes_data_tables/Sparkling_ID90_genekey_reclassified_2018-03-03.csv", row.names = F)

trout_key$Taxonomy <- as.character(trout_key$Taxonomy)
search <- match(trout_key$Genome, as.character(contigs$V1))
where_in_key <- which(is.na(search) == F)
where_in_contigs <- search[where_in_key]
matching_bins <- contigs$V2[where_in_contigs]
taxonomy_add <- as.character(bins$phylodist_taxonomy[match(matching_bins, bins$bin)])
trout_key$Taxonomy[where_in_key] <- taxonomy_add

write.csv(trout_key, "D:/geodes_data_tables/Trout_ID90_genekey_reclassified_2018-03-03.csv", row.names = F)
```

transcripts_per_liter.R
```{r, eval = F}
# Normalize table to transcripts/L

readCounts <- read.table("D:/geodes_data_tables/Trout_ID90_2018-03-02.readcounts.txt", header = T, row.names = 1, sep = " ")
sample_data <- read.csv("C:/Users/Alex/Desktop/geodes/bioinformatics_workflow/R_processing/sample_metadata.csv")

# Remove samples with poor std
std <- readCounts[which(rownames(readCounts) == "pFN18A_DNA_transcript"),]
readCounts2 <- readCounts[, which(std > 50)]
# Calculate standard normalization factor

std2 <- readCounts2[which(rownames(readCounts2) == "pFN18A_DNA_transcript"),]
std_factor <- std2/614000000

# Calculate volume factor

new_sample_data <- sample_data[match(substr(start = 1, stop = 9, colnames(readCounts2)), sample_data$Sample[1:109]), ]
vol_factor <- new_sample_data$Vol_Filtered

norm_val <- std_factor * vol_factor
# Normalize to transcripts/L

for(i in 1:length(norm_val)){
  readCounts2[,i] <- readCounts2[,i]/as.numeric(norm_val[i])
}

# Save normalized table
write.csv(readCounts2, "D:/geodes_data_tables/Trout_ID90_normalized_readcounts.csv", quote = F)


# Make a table summed by genome
# all_genomes <- substr(rownames(readCounts2), start = 1, stop = 10)
# genomes <- unique(all_genomes)
# genome_table <- readCounts2[1,]
# 
# for(i in 1:length(genomes)){
#   genes <- readCounts2[which(all_genomes == genomes[i]), ]
#   genome_row <- colSums(genes)
#   genome_table <- rbind(genome_table, genome_row)
# }
# 
# genome_table <- genome_table[2:267,]
# rownames(genome_table) <- genomes
# 
# # save genome table
# 
# write.csv(genome_table, "D:/geodes_data_tables/Trout_ID90_normalized_genomecounts.csv", quote = F)
# 

```

summary_stats.R
```{r, eval = F}
### Summary statistics on GEODES

### Load packages
library(ggplot2)
library(cowplot)
library(reshape2)
#library(GeneCycle)

### Load data (start with only one to save RAM and comment the rest out)
# Normalized read tables
snorm <- read.csv("D:/geodes_data_tables/Sparkling_ID90_normalized_readcounts.csv", header = T, row.names = 1)
tnorm <- read.csv("D:/geodes_data_tables/Trout_ID90_normalized_readcounts.csv", header = T, row.names = 1)
mnorm <- read.csv("D:/geodes_data_tables/Mendota_ID90_normalized_readcounts.csv", header = T, row.names = 1)

# Gene keys
mendota_key <- read.csv("D:/geodes_data_tables/Mendota_ID90_genekey_reclassified_2018-03-03.csv", header = T)
spark_key <- read.csv("D:/geodes_data_tables/Sparkling_ID90_genekey_reclassified_2018-03-03.csv", header = T)
trout_key <- read.csv("D:/geodes_data_tables/Trout_ID90_genekey_reclassified_2018-03-03.csv", header = T)

# Sample data
metadata <- read.csv(file = "C:/Users/Alex/Desktop/geodes/bioinformatics_workflow/R_processing/sample_metadata.csv", header = T)

# How expressed is each phylum?
mendota_key$Taxonomy <- gsub("Bacteria;", "", mendota_key$Taxonomy)
mendota_key$Taxonomy <- gsub("Eukaryota;", "", mendota_key$Taxonomy)
mendota_key$Phylum <- sapply(strsplit(as.character(mendota_key$Taxonomy),";"), `[`, 1)

mnorm$Genes <- rownames(mnorm)
mnorm <- melt(mnorm)
mnorm$variable <- gsub(".nonrRNA", "", mnorm$variable)
mnorm$Timepoint <- metadata$Timepoint[match(mnorm$variable, metadata$Sample)]
mnorm$Taxonomy <- mendota_key$Phylum[match(mnorm$Genes, mendota_key$Gene)]
mnorm$Taxonomy <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("NO CLASSIFICATION MH", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("NO CLASSIFICATION LP", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("NO CLASSIFICATION DUE TO FEW HITS IN PHYLODIST", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("None", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("unclassified unclassified", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("unclassified Oligohymenophorea", "Ciliophora", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("unclassified Pelagophyceae", "Ochrophyta", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("unclassified", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("Unclassified ", "Unclassified", mnorm$Taxonomy)
mnorm$Taxonomy <- gsub("UnclassifiedIsochrysidales", "Haptophyta", mnorm$Taxonomy)
averaged_tax <- aggregate(value ~ Taxonomy + Timepoint, data = mnorm, mean)
wide_mnorm <- reshape(averaged_tax, idvar = "Taxonomy", timevar = "Timepoint", direction = "wide")
rownames(wide_mnorm) <- wide_mnorm$Taxonomy
wide_mnorm <- wide_mnorm[, 2:dim(wide_mnorm)[2]]
wide_mnorm <- wide_mnorm[which(rowSums(wide_mnorm) > 3000),]

mendota_phyla <- data.frame(Taxonomy = rownames(wide_mnorm), Sums = rowSums(wide_mnorm))
mendota_phyla$Taxonomy <- c("Unclassified", "Acidobacteria", "Actinobacteria", "Armatimonadetes", "Bacteroidetes", "TM7", "Chlorobi", "Chloroflexi", "Chlorophyta", "Ciliophora", "Crenarchaeota", "Cryptophyta", "Cyanobacteria", "Deinococcus-Thermus", "Elusimicrobia", "Firmicutes", "Gemmatimonadetes", "Haptophyta", "Heterokonta", "Ignavibacteria", "standard", "Unclassified", "Planctomycetes", "Proteobacteria", "Spirochaetes", "Tenericutes", "Unclassified", "Verrucomicrobia", "Viruses")
unclassified <- mendota_phyla[which(mendota_phyla$Taxonomy == "Unclassified"), ]
mendota_phyla <- mendota_phyla[which(mendota_phyla$Taxonomy != "Unclassified"), ]
mendota_phyla <- rbind(mendota_phyla, c("Unclassified", sum(unclassified$Sums)))
mendota_phyla$Sums <- as.numeric(mendota_phyla$Sums)
mendota_phyla$Taxonomy <- factor(mendota_phyla$Taxonomy, levels = mendota_phyla$Taxonomy[order(mendota_phyla$Sums, decreasing = T)])
mendota_phyla <- mendota_phyla[which(mendota_phyla$Taxonomy != "standard"), ]
mendota_phyla$Type <- c("Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Protists", "Archaea", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Viruses", "Unclassified")


p <- ggplot(mendota_phyla, aes(x = Taxonomy, y = Sums, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Lake Mendota Metatranscriptomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/mendota_expression_by_phyla_reclassified_2018-03-03.pdf", p, base_height = 5, base_aspect_ratio = 1.5)

trout_key$Taxonomy <- gsub("Bacteria;", "", trout_key$Taxonomy)
trout_key$Taxonomy <- gsub("Eukaryota;", "", trout_key$Taxonomy)
trout_key$Phylum <- sapply(strsplit(as.character(trout_key$Taxonomy),";"), `[`, 1)

tnorm$Genes <- rownames(tnorm)
tnorm <- melt(tnorm)
tnorm$Timepoint <- metadata$Timepoint[match(tnorm$variable, metadata$Sample)]
tnorm$Taxonomy <- trout_key$Phylum[match(tnorm$Genes, trout_key$Gene)]
tnorm$Taxonomy <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("NO CLASSIFICATION MH", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("NO CLASSIFICATION LP", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("NO CLASSIFICATION DUE TO FEW HITS IN PHYLODIST", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("None", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("unclassified unclassified", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("unclassified Oligohymenophorea", "Ciliophora", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("unclassified Pelagophyceae", "Ochrophyta", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("unclassified", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("Unclassified ", "Unclassified", tnorm$Taxonomy)
tnorm$Taxonomy <- gsub("UnclassifiedIsochrysidales", "Haptophyta", tnorm$Taxonomy)
averaged_tax <- aggregate(value ~ Taxonomy + Timepoint, data = tnorm, mean)
wide_tnorm <- reshape(averaged_tax, idvar = "Taxonomy", timevar = "Timepoint", direction = "wide")
rownames(wide_tnorm) <- wide_tnorm$Taxonomy
wide_tnorm <- wide_tnorm[, 2:dim(wide_tnorm)[2]]
wide_tnorm <- wide_tnorm[which(rowSums(wide_tnorm) > 3000),]

trout_phyla <- data.frame(Taxonomy = rownames(wide_tnorm), Sums = rowSums(wide_tnorm))
trout_phyla$Taxonomy <- c("Acidobacteria", "Actinobacteria", "Armatimonadetes", "Arthropoda", "Bacteroidetes", "TM7", "Chlorobi", "Chloroflexi", "Chlorophyta", "Ciliophora", "Cryptophyta", "Cyanobacteria", "Deinococcus-Thermus", "Firmicutes", "Haptophyta", "Heterokonta", "Ignavibacteriae", "Unclassified", "Planctomycetes", "Proteobacteria", "Streptophyta", "Unclassified", "Verrucomicrobia", "Viruses")
unclassified <- trout_phyla[which(trout_phyla$Taxonomy == "Unclassified"), ]
trout_phyla <- trout_phyla[which(trout_phyla$Taxonomy != "Unclassified"), ]
trout_phyla <- rbind(trout_phyla, c("Unclassified", sum(unclassified$Sums)))
trout_phyla$Sums <- as.numeric(trout_phyla$Sums)
trout_phyla$Taxonomy <- factor(trout_phyla$Taxonomy, levels = trout_phyla$Taxonomy[order(trout_phyla$Sums, decreasing = T)])
trout_phyla$Type <- c("Bacteria", "Bacteria", "Bacteria", "Animals", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Fungi", "Algae", "Bacteria", "Bacteria", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria",  "Bacteria", "Algae", "Bacteria", "Viruses", "Unclassified")


p <- ggplot(trout_phyla, aes(x = Taxonomy, y = Sums, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Trout Bog Metatranscriptomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/trout_expression_by_phyla_reclassified_2018-03-03.pdf", p, base_height = 5, base_aspect_ratio = 1.5)

spark_key$Taxonomy <- gsub("Bacteria;", "", spark_key$Taxonomy)
spark_key$Taxonomy <- gsub("Eukaryota;", "", spark_key$Taxonomy)
spark_key$Phylum <- sapply(strsplit(as.character(spark_key$Taxonomy),";"), `[`, 1)

snorm$Genes <- rownames(snorm)
snorm <- melt(snorm)
snorm$Timepoint <- metadata$Timepoint[match(snorm$variable, metadata$Sample)]
snorm$Taxonomy <- spark_key$Phylum[match(snorm$Genes, spark_key$Gene)]
snorm$Taxonomy <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("NO CLASSIFICATION MH", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("NO CLASSIFICATION LP", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("None", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("NO CLASSIFICATION DUE TO FEW HITS IN PHYLODIST", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", snorm$Taxonomy)
snorm$Taxonomy <- gsub("unclassified unclassified", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("unclassified Oligohymenophorea", "Ciliophora", snorm$Taxonomy)
snorm$Taxonomy <- gsub("unclassified Pelagophyceae", "Ochrophyta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("unclassified", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("Unclassified ", "Unclassified", snorm$Taxonomy)
snorm$Taxonomy <- gsub("UnclassifiedIsochrysidales", "Haptophyta", snorm$Taxonomy)
snorm$Taxonomy <- gsub("UnclassifiedUnclassified", "Unclassified", snorm$Taxonomy)
averaged_tax <- aggregate(value ~ Taxonomy + Timepoint, data = snorm, mean)
wide_snorm <- reshape(averaged_tax, idvar = "Taxonomy", timevar = "Timepoint", direction = "wide")
rownames(wide_snorm) <- wide_snorm$Taxonomy
wide_snorm <- wide_snorm[, 2:dim(wide_snorm)[2]]
wide_snorm <- wide_snorm[which(rowSums(wide_snorm) > 3000),]

spark_phyla <- data.frame(Taxonomy = rownames(wide_snorm), Sums = rowSums(wide_snorm))
spark_phyla$Taxonomy <- c("Acidobacteria", "Actinobacteria", "Armatimonadetes", "Arthropoda", "Bacteroidetes", "TM7", "Chlorobi", "Chloroflexi", "Chlorophyta", "Ciliophora", "Cryptophyta", "Cyanobacteria", "Deinococcus-Thermus", "Firmicutes", "Haptophyta", "Heterokonta", "Ignavibacteria", "Unclassified", "Planctomycetes", "Proteobacteria", "Streptophyta", "Unclassified", "Verrucomicrobia", "Viruses")
unclassified <- spark_phyla[which(spark_phyla$Taxonomy == "Unclassified"), ]
spark_phyla <- spark_phyla[which(spark_phyla$Taxonomy != "Unclassified"), ]
spark_phyla <- rbind(spark_phyla, c("Unclassified", sum(unclassified$Sums)))
spark_phyla$Sums <- as.numeric(spark_phyla$Sums)
spark_phyla$Taxonomy <- factor(spark_phyla$Taxonomy, levels = spark_phyla$Taxonomy[order(spark_phyla$Sums, decreasing = T)])
spark_phyla$Type <- c("Bacteria", "Bacteria", "Bacteria", "Animals", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Protists", "Algae", "Bacteria", "Bacteria", "Bacteria",  "Algae", "Algae", "Bacteria", "Bacteria", "Bacteria", "Algae", "Bacteria", "Viruses", "Unclassified")


p <- ggplot(spark_phyla, aes(x = Taxonomy, y = Sums, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Sparkling Lake Metatranscriptomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/spark_expression_by_phyla_reclassified_2018-03-03.pdf", p, base_height = 5, base_aspect_ratio = 1.5)

# How does expression compare to abundance (ie the metagenomes?)
# No internal standard in the metagenomes, so normalized by library size (or report in % reads)
metaG_reads <- read.table("D:/geodes_data_tables/GEODES_metaG_2018-01-26.readcounts.txt", row.names = 1, sep = "\t")
colnames(metaG_reads) <- c("GEODES005", "GEODES006", "GEODES057", "GEODES058", "GEODES117", "GEODES118", "GEODES165", "GEODES166", "GEODES167", "GEODES168")
metaG_key <- read.table("D:/geodes_data_tables/GEODES_metaG_genekey.txt", sep = "\t", quote = "")
colnames(metaG_key) <- c("Gene", "Genome", "Taxonomy", "Product")
lakekey <- c("Sparkling", "Sparkling", "Trout", "Trout", "Mendota", "Mendota", "Sparkling2009", "Sparkling2009", "Sparkling2009", "Sparkling2009")
metaG_reads <- sweep(metaG_reads, 2, colSums(metaG_reads), "/")

metaG_key$Taxonomy <- gsub("Bacteria;", "", metaG_key$Taxonomy)
metaG_key$Taxonomy <- gsub("Eukaryota;", "", metaG_key$Taxonomy)
metaG_key$Phylum <- sapply(strsplit(as.character(metaG_key$Taxonomy),";"), `[`, 1)

metaG_reads$Genes <- rownames(metaG_reads)
spark_metaG <- metaG_reads[,c(1,2, 11)]
trout_metaG <- metaG_reads[,c(3,4, 11)]
mendota_metaG <- metaG_reads[,c(5,6, 11)]
spark2_metaG <- metaG_reads[,c(7,8,9,10, 11)]

spark_metaG <- melt(spark_metaG)
trout_metaG <- melt(trout_metaG)
mendota_metaG <- melt(mendota_metaG)
spark2_metaG <- melt(spark2_metaG)

spark_metaG$Phylum <- metaG_key$Phylum[match(spark_metaG$Genes, metaG_key$Gene)]
spark_metaG$Phylum <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified unclassified unclassified", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("NO CLASSIFICATION MH", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("NO CLASSIFICATION LP", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("None", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified unclassified", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified Oligohymenophorea", "Ciliophora", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified Pelagophyceae", "Ochrophyta", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("unclassified", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("Unclassified ", "Unclassified", spark_metaG$Phylum)
spark_metaG$Phylum <- gsub("UnclassifiedIsochrysidales", "Haptophyta", spark_metaG$Phylum)
spark_metaG$Phylum[which(is.na(spark_metaG$Phylum))] <- "Unclassified"
spark_phyla <- aggregate(value ~ Phylum, data = spark_metaG, mean)

spark_phyla$Type <- c("Unclassified", "Bacteria", "Bacteria", "Bacteria", "Animals", "Fungi", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Fungi", "Protists", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria",  "Bacteria", "Bacteria", "Algae", "Protists", "Algae", "Bacteria", "Animals", "Bacteria", "Bacteria", "Algae", "Bacteria", "Unclassified", "Bacteria", "Viruses")

spark_phyla$Phylum <- factor(spark_phyla$Phylum, levels = spark_phyla$Phylum[order(spark_phyla$value, decreasing = T)])

p <- ggplot(spark_phyla, aes(x = Phylum, y = value, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Sparkling Lake Metagenomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/spark_metagenome_by_phyla_reclassified.pdf", p, base_height = 5, base_aspect_ratio = 1.6)

trout_metaG$Phylum <- metaG_key$Phylum[match(trout_metaG$Genes, metaG_key$Gene)]
trout_metaG$Phylum <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified unclassified unclassified", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("NO CLASSIFICATION MH", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("NO CLASSIFICATION LP", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("None", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified unclassified", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified Oligohymenophorea", "Ciliophora", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified Pelagophyceae", "Ochrophyta", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("unclassified", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("Unclassified ", "Unclassified", trout_metaG$Phylum)
trout_metaG$Phylum <- gsub("UnclassifiedIsochrysidales", "Haptophyta", trout_metaG$Phylum)
trout_metaG$Phylum[which(is.na(trout_metaG$Phylum) == T)] <- "Unclassified"
trout_phyla <- aggregate(value ~ Phylum, data = trout_metaG, mean)

trout_phyla$Type <- c("Unclassified", "Bacteria", "Bacteria", "Bacteria", "Animals", "Fungi", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Fungi", "Protists", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria",  "Bacteria", "Bacteria", "Algae", "Protists", "Algae", "Bacteria", "Animals", "Bacteria", "Bacteria", "Algae", "Bacteria", "Unclassified", "Bacteria", "Viruses")

trout_phyla$Phylum <- factor(trout_phyla$Phylum, levels = trout_phyla$Phylum[order(trout_phyla$value, decreasing = T)])

p <- ggplot(trout_phyla, aes(x = Phylum, y = value, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Trout Bog Metagenomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/trout_metagenome_by_phyla_reclassified.pdf", p, base_height = 5, base_aspect_ratio = 1.6)

mendota_metaG$Phylum <- metaG_key$Phylum[match(mendota_metaG$Genes, metaG_key$Gene)]
mendota_metaG$Phylum <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified unclassified unclassified", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("NO CLASSIFICATION MH", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("NO CLASSIFICATION LP", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("None", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified unclassified", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified Oligohymenophorea", "Ciliophora", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified Pelagophyceae", "Ochrophyta", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("unclassified", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("Unclassified ", "Unclassified", mendota_metaG$Phylum)
mendota_metaG$Phylum <- gsub("UnclassifiedIsochrysidales", "Haptophyta", mendota_metaG$Phylum)
mendota_metaG$Phylum[which(is.na(mendota_metaG$Phylum) == T)] <- "Unclassified"
mendota_phyla <- aggregate(value ~ Phylum, data = mendota_metaG, mean)

mendota_phyla$Type <- c("Unclassified", "Bacteria", "Bacteria", "Bacteria", "Animals", "Fungi", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Fungi", "Protists", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria",  "Bacteria", "Bacteria", "Algae", "Protists", "Algae", "Bacteria", "Animals", "Bacteria", "Bacteria", "Algae", "Bacteria", "Unclassified", "Bacteria", "Viruses")

mendota_phyla$Phylum <- factor(mendota_phyla$Phylum, levels = mendota_phyla$Phylum[order(mendota_phyla$value, decreasing = T)])

p <- ggplot(mendota_phyla, aes(x = Phylum, y = value, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Mendota Metagenomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/mendota_metagenome_by_phyla_reclassified.pdf", p, base_height = 5, base_aspect_ratio = 1.6)

spark2_metaG$Phylum <- metaG_key$Phylum[match(spark2_metaG$Genes, metaG_key$Gene)]
spark2_metaG$Phylum <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified unclassified unclassified unclassified", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified unclassified unclassified", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("NO CLASSIFICATION MH", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("NO CLASSIFICATION LP", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("None", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified unclassified", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified Oligohymenophorea", "Ciliophora", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified Pelagophyceae", "Ochrophyta", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("unclassified", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("Unclassified ", "Unclassified", spark2_metaG$Phylum)
spark2_metaG$Phylum <- gsub("UnclassifiedIsochrysidales", "Haptophyta", spark2_metaG$Phylum)
spark2_metaG$Phylum[which(is.na(spark2_metaG$Phylum) == T)] <- "Unclassified"
spark2_phyla <- aggregate(value ~ Phylum, data = spark2_metaG, mean)

spark2_phyla$Type <- c("Unclassified", "Bacteria", "Bacteria", "Bacteria", "Animals", "Fungi", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Fungi", "Protists", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria",  "Bacteria", "Bacteria", "Algae", "Protists", "Algae", "Bacteria", "Animals", "Bacteria", "Bacteria", "Algae", "Bacteria", "Unclassified", "Bacteria", "Viruses")

spark2_phyla$Phylum <- factor(spark2_phyla$Phylum, levels = spark2_phyla$Phylum[order(spark2_phyla$value, decreasing = T)])

p <- ggplot(spark2_phyla, aes(x = Phylum, y = value, fill = Type)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, vjust = 0, hjust = 1)) + scale_fill_brewer(palette = "Set2") + labs(x = "", y = "Read Counts", title = "Sparkling Lake 2009 Metagenomes")

save_plot("C:/Users/Alex/Desktop/geodes/Plots/spark09_metagenome_by_phyla_reclassified.pdf", p, base_height = 5, base_aspect_ratio = 1.6)

# What are the top expressed genes?

totals <- rowSums(snorm)
top10 <- rownames(snorm)[order(totals, decreasing = T)]
top10 <- top10[2:11]
spark_key[match(top10, spark_key$Gene),]

totals <- rowSums(mnorm)
top10 <- rownames(mnorm)[order(totals, decreasing = T)]
top10 <- top10[2:11]
mendota_key[match(top10, mendota_key$Gene),]

totals <- rowSums(tnorm)
top10 <- rownames(tnorm)[order(totals, decreasing = T)]
top10 <- top10[2:11]
trout_key[match(top10, trout_key$Gene),]

# How abundant are the bins?
bins <- read.csv("D:/geodes_data_tables/GEODES_bin_data.csv", header = T)
contigs <- read.table("D:/geodes_data_tables/GEODES_binned_contigs.txt")

# only look at reasonable quality bins:
bins <- bins[which(bins$completeness > 30),]
bins <- bins[which(bins$contamination < 10),]
contigs <- contigs[which(contigs$V2 %in% bins$bin),]

# For each bin:
# grab the contigs in that bin
# grab the genes in those contigs
# count up read counts for those genes
ME_sum <- c()
SP_sum <- c()
TB_sum <- c()

for(i in 1:length(bins$bin)){
  bits <- contigs$V1[which(contigs$V2 == bins$bin[i])]
  ME_genes <- mendota_key$Gene[which(mendota_key$Genome %in% bits)]
  ME_sum[i] <- sum(rowSums(mnorm[which(rownames(mnorm) %in% ME_genes),]))
  SP_genes <- spark_key$Gene[which(spark_key$Genome %in% bits)]
  SP_sum[i] <- sum(rowSums(snorm[which(rownames(snorm) %in% ME_genes),]))
  TB_genes <- trout_key$Gene[which(trout_key$Genome %in% bits)]
  TB_sum[i] <- sum(rowSums(tnorm[which(rownames(tnorm) %in% ME_genes),]))
}

bin_counts <- data.frame(bins$bin, ME_sum, SP_sum, TB_sum)
colnames(bin_counts) <- c("Bin", "Mendota", "Sparkling", "Trout")
bin_counts$Taxonomy <- bins$phylodist_taxonomy[match(bin_counts$Bin, bins$bin)]
bin_counts <- bin_counts[which(bin_counts$Mendota > 0 | bin_counts$Sparkling > 0 | bin_counts$Trout > 0),]
bin_counts$Phylum <- sapply(strsplit(as.character(bin_counts$Taxonomy),";"), `[`, 2)
bin_counts$Phylum[which(is.na(bin_counts$Phylum) == T)] <- "Unclassified"

bin_counts$Bin <- factor(bin_counts$Bin, levels = bin_counts$Bin[order(bin_counts$Mendota, decreasing = T)])
ggplot(data = bin_counts, aes(x = Bin, y = Mendota, fill = Phylum)) + geom_bar(stat = "identity") + scale_y_log10() + labs(title = "Mendota") + theme(axis.text.x = element_text(angle = 90, hjust = 1))

ggplot(data = bin_counts, aes(x = Phylum, y = Mendota, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Mendota", x = "Bin Phylum Assignment", y = "Metatranscriptomic Read Counts") 

ggplot(data = bin_counts, aes(x = Phylum, y = Sparkling, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Sparkling", x = "Bin Phylum Assignment", y = "Metatranscriptomic Read Counts") 

ggplot(data = bin_counts, aes(x = Phylum, y = Trout, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Trout Bog", x = "Bin Phylum Assignment", y = "Metatranscriptomic Read Counts") 

# Repeat with metagenomic read counts
# run the following code if you skipped the earlier code on metagenomes:
metaG_reads <- read.table("D:/geodes_data_tables/GEODES_metaG_2018-01-26.readcounts.txt", row.names = 1, sep = "\t")
colnames(metaG_reads) <- c("GEODES005", "GEODES006", "GEODES057", "GEODES058", "GEODES117", "GEODES118", "GEODES165", "GEODES166", "GEODES167", "GEODES168")
metaG_key <- read.table("D:/geodes_data_tables/GEODES_metaG_genekey.txt", sep = "\t", quote = "")
colnames(metaG_key) <- c("Gene", "Genome", "Taxonomy", "Product")
lakekey <- c("Sparkling", "Sparkling", "Trout", "Trout", "Mendota", "Mendota", "Sparkling2009", "Sparkling2009", "Sparkling2009", "Sparkling2009")
metaG_reads <- sweep(metaG_reads, 2, colSums(metaG_reads), "/")

ME_metaG <- c()
SP_metaG <- c()
TB_metaG <- c()
SP_metaG2 <- c()

for(i in 1:length(bins$bin)){
  bits <- contigs$V1[which(contigs$V2 == bins$bin[i])]
  genes <- metaG_key$Gene[which(metaG_key$Genome %in% bits)]
  reads <- metaG_reads[which(rownames(metaG_reads) %in% genes),]
  ME_metaG[i] <- sum(rowSums(reads[,which(lakekey == "Mendota")]))
  SP_metaG[i] <- sum(rowSums(reads[,which(lakekey == "Sparkling")]))
  TB_metaG[i] <- sum(rowSums(reads[,which(lakekey == "Trout")]))
  SP_metaG2[i] <- sum(rowSums(reads[,which(lakekey == "Sparkling2009")]))
}

bin_counts <- data.frame(bins$bin)
bin_counts$Mendota_metaG <- ME_metaG
bin_counts$Sparkling_metaG <- SP_metaG
bin_counts$Trout_metaG <- TB_metaG
bin_counts$Sparkling09_metaG <- SP_metaG2

bin_counts$Taxonomy <- bins$phylodist_taxonomy[match(bin_counts$bin, bins$bin)]
bin_counts$Phylum <- sapply(strsplit(as.character(bin_counts$Taxonomy),";"), `[`, 2)
bin_counts$Phylum[which(is.na(bin_counts$Phylum) == T)] <- "Unclassified"

ggplot(data = bin_counts, aes(x = Phylum, y = Mendota_metaG, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Mendota", x = "Bin Phylum Assignment", y = "Metagenomic Read Counts") 

ggplot(data = bin_counts, aes(x = Phylum, y = Sparkling_metaG, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Sparkling", x = "Bin Phylum Assignment", y = "Metagenomic Read Counts") 

ggplot(data = bin_counts, aes(x = Phylum, y = Trout_metaG, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Trout Bog", x = "Bin Phylum Assignment", y = "Metagenomic Read Counts") 

ggplot(data = bin_counts, aes(x = Phylum, y = Sparkling09_metaG, fill = Phylum)) + geom_bar(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1), legend.position = "none") + labs(title = "Sparkling 2009", x = "Bin Phylum Assignment", y = "Metagenomic Read Counts")

```
