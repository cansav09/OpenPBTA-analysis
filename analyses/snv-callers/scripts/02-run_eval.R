# Plot the variant caller data and print out a report html file.
#
# 2019
#
# C. Savonen for ALSF - CCDL
#
# Option descriptions
# --label : Label to be used for folder and all output. eg. 'strelka2'. Optional.
#      Default is 'maf'
# --plot_type : Specify what kind of plots you want printed out. Must be
#               compatible with ggsave. eg pdf. Default is png
# --vaf : Folder from 01-calculate_vaf_tmb.R following files:
#                                             <caller_name>_vaf.<file_format>
#                                             <caller_name>_region.<file_format>
#                                             <caller_name>_tmb.<file_format>
# --file_format: What type of file format were the vaf and tmb files saved as? Options are
#               "rds" or "tsv". Default is "rds".
# --output : Where you would like the output from this script to be stored.
# --strategy : Specify whether you would like WXS and WGS separated for the plots.
#              Analysis is still done on all data in the MAF file regardless.
#              Acceptable options are 'wgs', 'wxs' or 'both', both for if you
#              don't want to separate them. Default is both.
# --cosmic : Relative file path to COSMIC file to be analyzed. Assumes file path
#            is given from top directory of 'OpenPBTA-analysis'.
# --overwrite : If TRUE, will overwrite any reports of the same name. Default is
#              FALSE
# --no_region : If used, regional analysis will not be done.

#
# Command line example:
#
# Rscript 02-run_eval.R \
# -l strelka2 \
# -p png \
# -o strelka2 \
# -s wxs \
# -w
#
# Establish base dir
root_dir <- rprojroot::find_root(rprojroot::has_dir(".git"))

# Magrittr pipe
`%>%` <- dplyr::`%>%`

# Import special functions
source(file.path(root_dir, "analyses", "snv-callers", "util", "wrangle_functions.R"))
source(file.path(root_dir, "analyses", "snv-callers", "util", "plot_functions.R"))

# Load library:
library(optparse)

#--------------------------------Set up options--------------------------------#
# Set up optparse options
option_list <- list(
  make_option(
    opt_str = c("-l", "--label"), type = "character",
    default = "maf", help = "Label to be used for folder and all
                output. eg. 'strelka2'. Optional. Default is 'maf'",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-p", "--plot_type"), type = "character",
    default = "png", help = "Specify what kind of plots you want
                printed out. Must be compatible with ggsave. eg pdf.
                Default is png.",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-v", "--vaf"), type = "character",
    default = NULL, help = "Path to folder with the output files
              from 01-calculate_vaf_tmb. Should include the VAF, TMB, and
              region TSV files",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-f", "--file_format"), type = "character", default = "rds",
    help = "What type of file format were the vaf and tmb files saved as?
            Options are 'rds' or 'tsv'. Default is 'rds'.",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-o", "--output"), type = "character",
    default = NULL, help = "Path to folder where you would like the
              output from this script to be stored.",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-s", "--strategy"), type = "character",
    default = "both", help = "Specify whether you would like WXS and
                WGS separated for the plots. Can state all three with commas in
                between such as 'wgs,wxs,both'. Acceptable options are 'wgs',
                'wxs' or 'both', both for if you don't want to separate them.
                Default is both.",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-c", "--cosmic"), type = "character", default = "none",
    help = "Relative file path (assuming from top directory of
              'OpenPBTA-analysis') to COSMIC file to be analyzed.",
    metavar = "character"
  ),
  make_option(
    opt_str = c("-w", "--overwrite"), action = "store_true",
    default = FALSE, help = "If TRUE, will overwrite any reports of
              the same name. Default is FALSE",
    metavar = "character"
  ),
  make_option(
    opt_str = "--no_region", action = "store_false",
    default = TRUE, help = "If used, regional analysis will not be run.",
    metavar = "character"
  )
)

# Parse options
opt <- parse_args(OptionParser(option_list = option_list))

# Bring along the file suffix. Make to lower.
file_suffix <- tolower(opt$file_format)

# Check that the file format is supported
if (!(file_suffix %in% c("rds", "tsv"))) {
  warning("Option used for file format (-f) is not supported. Only 'tsv' or 'rds'
          files are supported. Defaulting to rds.")
  opt$file_format <- "rds"
  file_suffix <- "rds"
}

########################### Check options specified ############################
# Normalize this file path
opt$vaf <- file.path(root_dir, opt$vaf)

# Check the output directory exists
if (!dir.exists(opt$vaf)) {
  stop(paste("Error:", opt$vaf, "does not exist"))
}

# Obtain the file list so we can check for the necessary files
file_list <- dir(opt$vaf)

# The list of needed file suffixes
needed_files <- c(paste0("_vaf.", file_suffix), paste0("_tmb.", file_suffix), opt$cosmic)

if (opt$no_region) {
  needed_files <- c(needed_files, paste0("_region.", file_suffix))
}
# Get list of which files were found
files_found <- sapply(needed_files, function(file_suffix) {
  grep(file_suffix, file_list, value = TRUE)
})

# Report error if any of them aren't found
if (any(is.na(files_found))) {
  stop(paste0(
    "Error: the directory specified with --output, doesn't have the",
    "necessary file(s):", names(files_found)[which(!files_found)]
  ))
}

# Specify the exact paths of these files
file_list <- file.path(opt$vaf, files_found)

# List plot types we can take. This is base on ggsave's documentation
acceptable_plot_types <- c(
  "eps", "ps", "tex", "pdf", "jpeg", "tiff", "png",
  "bmp", "svg"
)

# Check the plot type option
if (!(opt$plot_type %in% acceptable_plot_types)) {
  stop("Error: unrecognized plot type specified. Only plot types accepted by
       ggplot2::ggsave may be used.")
}
# Add the period
opt$plot_type <- paste0(".", opt$plot_type)

################################### Set Up #####################################
# Set and make the plots directory
opt$output <- file.path(root_dir, opt$output)

# Make caller specific plots folder
if (!dir.exists(opt$output)) {
  dir.create(opt$output, recursive = TRUE)
}

# Make a list of the plot suffixes
plot_suffixes <- c("_base_change", "_depth_vs_vaf", "_cosmic_plot", "_tmb_plot")

if (opt$no_region) {
  plot_suffixes <- c(plot_suffixes, "_snv_region")
}

# Make the plot names with specified prefix
plot_names <- paste0(plot_suffixes, opt$plot_type)

# Read in these data
if (opt$file_format == "tsv") {
  vaf_df <- readr::read_tsv(grep("_vaf.tsv$", file_list, value = TRUE))
  tmb_df <- readr::read_tsv(grep("_tmb.tsv$", file_list, value = TRUE))
} else {
  vaf_df <- readr::read_rds(grep("_vaf.rds$", file_list, value = TRUE))
  tmb_df <- readr::read_rds(grep("_tmb.rds$", file_list, value = TRUE))
}

# Only read in the regional things if that is necessary
if (opt$no_region) {
  if (opt$file_format == "tsv") {
    maf_annot <- readr::read_tsv(grep("_region.tsv$", file_list, value = TRUE))
  } else {
    maf_annot <- readr::read_rds(grep("_region.rds$", file_list, value = TRUE))
  }
}
######################## Check VAF file for each strategy ######################

# Reformat the strategy option into lower case and vector
opt$strategy <- tolower(unlist(strsplit(opt$strategy, ",")))

# Check strategy options
if (!all(opt$strategy %in% c("wgs", "wxs", "both"))) {
  stop("Error: unrecognized --strategy option. Acceptable options are 'wgs',
       'wxs' or 'both'. Multiple can be specified at once.")
}

# Check for WGS or WXS samples
ind_strategies <- grep("wgs|wxs", opt$strategy, value = TRUE)

# Check that these strategies exist in this file
strategies_found <- ind_strategies %in% tolower(vaf_df$experimental_strategy)

# If any of the strategies wasn't found, exclude them from the report list and
# don't try to make a "both" report.
if (any(!strategies_found)) {
  # Print out warning:
  warning(paste(
    "Only samples that are", toupper(ind_strategies[strategies_found]),
    "were found. Only a", toupper(ind_strategies[strategies_found]),
    "will be made."
  ))

  # Make the original strategies list only the ones that were found.
  opt$strategy <- ind_strategies[strategies_found]
}
#################### Run this for each experimental strategy ###################
for (strategy in opt$strategy) {
  # File paths plots we will create
  plot_paths <- file.path(
    opt$output,
    paste0(opt$label, "_", strategy, plot_names)
  )
  # Bring along the plot names
  names(plot_paths) <- plot_names

  ################## Plot the data using special functions #####################
  # Base call barplot
  base_change_plot(vaf_df, exp_strategy = strategy)
  ggplot2::ggsave(filename = plot_paths["_base_change.png"], plot = ggplot2::last_plot())

  # Read depth and VAF
  depth_vs_vaf_plot(vaf_df, exp_strategy = strategy)
  ggplot2::ggsave(filename = plot_paths["_depth_vs_vaf.png"], plot = ggplot2::last_plot())

  # Percent variants in COSMIC
  cosmic_plot(vaf_df, exp_strategy = strategy, opt$cosmic)
  ggplot2::ggsave(filename = plot_paths["_cosmic_plot.png"], plot = ggplot2::last_plot())

  # TMB by histology
  tmb_plot(tmb_df, x_axis = "short_histology", exp_strategy = strategy)
  ggplot2::ggsave(filename = plot_paths["_tmb_plot.png"], plot = ggplot2::last_plot())

  if (opt$no_region) {
    # Genomic region breakdown
    snv_region_plot(maf_annot, exp_strategy = strategy)
    ggplot2::ggsave(filename = plot_paths["_snv_region.png"], plot = ggplot2::last_plot())
  }

  ######################## Make plots into a report ############################
  # Make a summary report about the variant caller and strategy
  output_file <- file.path(
    opt$output,
    paste0(opt$label, "_", strategy, "_report.Rmd")
  )

  # Path to the template file
  template_folder <- file.path(
    root_dir, "analyses", "snv-callers", "template"
  )

  # Designate which template file name
  if (opt$no_region) {
    template_file <- file.path(template_folder, "variant_caller_report_template.Rmd")
  } else {
    template_file <- file.path(template_folder, "variant_caller_report_no_region_template.Rmd")
  }

  # Make copy of template
  if (file.exists(template_file)) {
    file.copy(from = template_file, to = output_file, overwrite = opt$overwrite)
  } else {
    stop(cat("The Rmd template file ", template_file, " does not exist."))
  }

  # Run this notebook
  rmarkdown::render(output_file, "html_document")
}
