# J. Taroni for CCDL 2019
# This script takes a directory of OpenPBTA files to subset and produces a list
# of biospecimen IDs, saved as an RDS file, to use to subset the files for
# use in continuous integration.
#
# This list will have the following features, where each element is a vector
# of biospecimen IDs to be extracted from a file:
#
#   - Some number of biospecimen IDs that correspond to participant IDs that
#     are represented across experimental strategies. The number of participant
#     IDs used to accomplish this is specified with the num_matched parameter.
#     Poly-A samples will be somewhat overrepresented vs. the portion of total
#     RNA-seq samples they make up.
#   - Some number of biospecimen IDs that correspond to participant IDs that
#     are *not* represented across strategies but are present in the file under
#     consideration. This number will be 10% of num_matched.
#
# EXAMPLE USAGE:
#
#   Rscript analyses/create-subset-files/01-get_biospecimen_identifiers.R \
#     --data_directory data/release-v5-20190924 \
#     --output_file analyses/create-subset-files/biospecimen_ids_for_subset.RDS \
#     --supported_string "pbta-snv|pbta-cnv|pbta-fusion|pbta-isoform|pbta-sv|pbta-gene" \
#     --num_matched 25 \
#     --seed 2019

#### Library and functions -----------------------------------------------------

library(readr)
library(optparse)

`%>%` <- dplyr::`%>%`

get_biospecimen_ids <- function(filename, id_mapping_df) {
  # Given a supported OpenPBTA file, return the participant IDs corresponding
  # to the biospecimen IDs contained within that file
  #
  # Args:
  #   filename: the full path to a supported OpenPBTA file
  #   id_mapping_df: the data.frame that contains mapping between biospecimen
  #                  IDs and participant IDs
  #
  # Returns:
  #   a vector of unique participant IDs

  message(paste("Reading in", filename, "..."))

  # where the biospecimen IDs come from in each file depends on the file
  # type -- that is why we need all of this logic
  if (grepl("pbta-snv", filename)) {
    # in a column 'Tumor_Sample_Barcode'
    snv_file <- data.table::fread(filename,
                                  skip = 1,  # skip version string
                                  data.table = FALSE)
    biospecimen_ids <- unique(snv_file$Tumor_Sample_Barcode)
  } else if (grepl("pbta-cnv", filename)) {
    # in a column 'ID'
    cnv_file <- read_tsv(filename)
    biospecimen_ids <- unique(cnv_file$ID)
  } else if (grepl("pbta-fusion", filename)) {
    # in a column 'tumor_id'
    fusion_file <- read_tsv(filename)
    biospecimen_ids <- unique(fusion_file$tumor_id)
  } else if (grepl("pbta-sv", filename)) {
    # in a column 'Kids.First.Biospecimen.ID.Tumor'
    sv_file <- data.table::fread(filename, data.table = FALSE)
    biospecimen_ids <- unique(sv_file$Kids.First.Biospecimen.ID.Tumor)
  } else if (grepl(".rds", filename)) {
    # any column name that contains 'BS_' is a biospecimen ID
    expression_file <- read_rds(filename) %>%
      dplyr::select(dplyr::contains("BS_"))
    biospecimen_ids <- unique(colnames(expression_file))
  } else {
    # error-handling
    stop("File type unrecognized by 'get_biospecimen_ids'")
  }

  # map from biospecimen ID to participant IDs and return unique participant IDs
  participant_ids <-  id_mapping_df %>%
    dplyr::filter(Kids_First_Biospecimen_ID %in% biospecimen_ids) %>%
    dplyr::pull(Kids_First_Participant_ID)
  return(unique(participant_ids))

}

#### Command line arguments/options --------------------------------------------

# Declare command line options
option_list <- list(
  make_option(
    c("-d", "--data_directory"),
    type = "character",
    default = NULL,
    help = "directory that contains data files to subset",
  ),
  make_option(
    c("-o", "--output_file"),
    type = "character",
    default = NULL,
    help = "output RDS file"
  ),
  make_option(
    c("-r", "--supported_string"),
    type = "character",
    default = "pbta-snv|pbta-cnv|pbta-fusion|pbta-isoform|pbta-sv|pbta-gene",
    help = "string for pattern matching used to subset to only supported files"
  ),
  make_option(
    c("-p", "--num_matched"),
    type = "integer",
    default = 25,
    help = "number of matched participants",
    metavar = "integer"
  ),
  make_option(
    c("-s", "--seed"),
    type = "integer",
    default = 2019,
    help = "seed integer",
    metavar = "integer"
  )
)

# Read the arguments passed
opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# set up required arguments: input directory and output file
data_directory <- opt$data_directory
output_file <- opt$output_file

# string that will be used for pattern matching to select the files for
# subsetting
supported_files_string <- opt$supported_string

# get numbers of matched participants
num_matched_participants <- opt$num_matched
num_matched_polya <- ceiling(0.2 * num_matched_participants)
num_matched_stranded <- num_matched_participants - num_matched_polya

# extra non-matched samples -- this is a realistic scenario and will test for
# brittleness of code up for review
num_nonmatched <- ceiling(0.1 * num_matched_participants)

# set the seed
set.seed(opt$seed)

#### Get IDs -------------------------------------------------------------------

# list all files we are interested in subsetting and can support
files_to_subset <- list.files(data_directory,
                              pattern = supported_files_string,
                              full.names = TRUE)

# get the participant ID to biospecimen ID
id_mapping_df <- read_tsv(file.path(data_directory, "pbta-histologies.tsv")) %>%
  dplyr::select(Kids_First_Participant_ID, Kids_First_Biospecimen_ID) %>%
  dplyr::distinct()

# for each file, extract the participant ID list by first obtaining the
# biospecimen IDs and then mapping back to
participant_id_list <- purrr::map(files_to_subset,
                                  ~ get_biospecimen_ids(.x, id_mapping_df)) %>%
  stats::setNames(files_to_subset)

# split up information for poly-A and stranded expression data vs. all else
polya_participant_list <- purrr::keep(
  participant_id_list,
  grepl("polya",
        names(participant_id_list))
)

stranded_participant_list <- purrr::keep(
  participant_id_list,
  grepl("stranded",
        names(participant_id_list))
)

other_strategy_participant_list <- purrr::discard(
  participant_id_list,
  grepl("polya|stranded",
        names(participant_id_list))
)

# find samples that are common to all files
polya_in_all <- purrr::reduce(polya_participant_list, intersect)
stranded_in_all <- purrr::reduce(stranded_participant_list, intersect)
other_strategy_in_all <- purrr::reduce(other_strategy_participant_list,
                                       intersect)

# find RNA-seq samples that have matched samples in other strategies
polya_matched <- intersect(polya_in_all, other_strategy_in_all)
stranded_matched <- intersect(stranded_in_all, other_strategy_in_all)

# find identifiers for matched participants
polya_for_subset <- sample(polya_matched, num_matched_polya)
stranded_for_subset <- sample(stranded_matched, num_matched_stranded)
matched_for_subset <- purrr::map(participant_id_list,
                                 ~ intersect(.x, c(polya_for_subset,
                                                   stranded_for_subset)))

# get a list of samples that are not in these matched lists to use to subset
nonmatched_for_subset <-
  purrr::map(participant_id_list,
             ~ setdiff(.x, c(polya_matched, stranded_matched))) %>%
  purrr::map(~ sample(.x, num_nonmatched))

# combine the matched and nonmatched lists of ids for subsetting
participant_ids_for_subset <- purrr::map2(matched_for_subset,
                                          nonmatched_for_subset,
                                          c)

# map back to biospecimen ids + save to file
biospecimen_ids_for_subset <- purrr::map(
  participant_ids_for_subset,
  function(x) {
    id_mapping_df %>%
      dplyr::filter(Kids_First_Participant_ID %in% x) %>%
      dplyr::pull(Kids_First_Biospecimen_ID)
  }
) %>%
  write_rds(output_file)
