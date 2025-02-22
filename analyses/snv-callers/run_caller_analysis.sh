#!/bin/bash
# C. Savonen
# CCDL for ALSF 2019

# Purpose:Run an intial evaluation of each variant caller's MAF file

# Set this so the whole loop stops if there is an error
set -e
set -o pipefail

# The files named in these arrays will be ran in the analysis. 
datasets=("strelka2" "mutect2" "lancet" "vardict")
wgs_files=("WGS.hg38.strelka2.unpadded.bed" "WGS.hg38.mutect2.unpadded.bed" "WGS.hg38.lancet.300bp_padded.bed" "WGS.hg38.vardict.100bp_padded.bed")

# Reference file paths
cosmic=analyses/snv-callers/ref_files/brain_cosmic_variants_coordinates.tsv
annot_rds=analyses/snv-callers/ref_files/hg38_genomic_region_annotation.rds

# Choose TSV or RDS
format=rds

# Set a default for the VAF filter if none is specified
vaf_cutoff=${OPENPBTA_VAF_CUTOFF:-0}

############################ Set Up Reference Files ############################
# The original COSMIC file is obtained from: https://cancer.sanger.ac.uk/cosmic/download
# These data are available if you register. The full, unfiltered somatic mutations 
# file CosmicMutantExport.tsv.gz for grch38 is used here.
Rscript analyses/snv-callers/scripts/00-set_up.R \
  --annot_rds $annot_rds \
  --cosmic_og scratch/CosmicMutantExport.tsv.gz \
  --cosmic_clean $cosmic
  
########################## Calculate and Set Up Data ##########################
# Create files that contain calculated VAF, TMB, and regional analyses.
for ((i=0;i<${#datasets[@]};i++)); 
do
  echo "Processing dataset: ${datasets[$i]}"
  Rscript analyses/snv-callers/scripts/01-calculate_vaf_tmb.R \
    --label ${datasets[$i]} \
    --output analyses/snv-callers/results/${datasets[$i]} \
    --file_format $format \
    --maf data/pbta-snv-${datasets[$i]}.vep.maf.gz \
    --metadata data/pbta-histologies.tsv \
    --bed_wgs data/${wgs_files[$i]} \
    --bed_wxs data/WXS.hg38.100bp_padded.bed \
    --annot_rds $annot_rds \
    --vaf_filter $vaf_cutoff \
    --no_region \
    --overwrite 
done
######################## Plot the data and create reports ######################
for dataset in ${datasets[@]}
 do
  echo "Processing dataset: ${dataset}"
  Rscript analyses/snv-callers/scripts/02-run_eval.R \
    --label ${dataset} \
    --vaf analyses/snv-callers/results/${dataset} \
    --plot_type png \
    --file_format $format \
    --output analyses/snv-callers/plots/${dataset} \
    --cosmic $cosmic \
    --strategy wgs,wxs,both \
    --no_region
 done
##################### Merge callers' files into total files ####################
Rscript analyses/snv-callers/scripts/03-merge_callers.R \
  --vaf analyses/snv-callers/results \
  --output analyses/snv-callers/results/consensus \
  --file_format $format \
  --overwrite
