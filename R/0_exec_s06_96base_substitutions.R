#==================================================
# David Brown
# brownd7@mskcc.org
#==================================================
rm(list=ls(all=TRUE))
source('config.R')

if (!dir.exists("../res/figureS6")) {
	dir.create("../res/figureS6")
}

if (!dir.exists("../res/etc/Source_Data_Extended_Data_Fig_5")) {
	dir.create("../res/etc/Source_Data_Extended_Data_Fig_5")
}


#==================================================
# bar plot of mutational signatures
#==================================================
clinical = read_tsv(file=clinical_file, col_types = cols(.default = col_character())) %>%
		   type_convert() %>%
		   mutate(subj_type = ifelse(subj_type == "Healthy", "Control", subj_type))
		   
snv_vars = read_tsv(snv_file$scored, col_types = cols(.default = col_character())) %>%
		   type_convert() %>%
		   mutate(level_2a = as.character(level_2a)) %>%
		   mutate(level_r1 = as.character(level_r1))
		   
indel_vars = read_tsv(indel_file$scored, col_types = cols(.default = col_character())) %>%
			 type_convert() %>%
			 mutate(level_2a = as.character(level_2a)) %>%
		   	 mutate(level_r1 = as.character(level_r1))

wbc_stack = read_tsv(wbc_variants$scored, col_types = cols(.default = col_character())) %>%
			type_convert()
			
msk_anno = read_tsv(msk_anno_joined, col_types = cols(.default = col_character())) %>%
  		   type_convert()
			
tracker_grail = read_csv(file=patient_tracker)

tracker_impact = read_csv(file=impact_tracker)

bed_file = rtracklayer::import.bed(con=common_bed)
bed_ranges = GenomicRanges::ranges(bed_file)
total_bed_Mb = sum(GenomicRanges::width(bed_ranges)) / 1e6

valid_patient_ids = tracker_grail %>%
					filter(patient_id %in% tracker_impact$patient_id) %>%
					.[["patient_id"]]
  
indel_vars = indel_vars %>%
			 mutate(filter = replace(filter,
             		patient_id == "MSK-VB-0001" &
             		gene == "GATA3" &
             		filter == "PASS",
             		"CSR_MATCH_ELIMINATED"),
         	 		ccd = replace(ccd,
             			   		  patient_id == "MSK-VB-0001" &
                           		  gene == "GATA3" &
                           		  filter == "CSR_MATCH_ELIMINATED",
                           		  0))

snv_plasma = snv_vars %>%
  			 filter(ccd == 1,
         			(c_panel == 1 | panel == 1),
         			study == "TechVal",
         			grail == 1 | MSK == 1,
         			patient_id %in% valid_patient_ids) %>%
			 mutate(vtype = "SNV")

indel_plasma = indel_vars %>%
			   filter(ccd == 1,
         			  (c_panel == 1 | panel == 1),
         			  study == "TechVal",
         			  grail == 1 | MSK == 1,
         			  patient_id %in% valid_patient_ids) %>%
  			   mutate(vtype = "INDEL",
         			  altenddistmedian = as.integer(altenddistmedian))
         			  
healthy_snv = snv_vars %>%
  			  filter((c_panel == 1 | panel == 1),
         			  subj_type == "Healthy",
         			  grail == 1) %>%
  			  mutate(vtype = "SNV")

healthy_indel = indel_vars %>%
  				filter((c_panel == 1 | panel == 1),
         			    subj_type == "Healthy",
         				grail == 1) %>%
  				mutate(vtype = "INDEL",
         			   altenddistmedian = as.integer(altenddistmedian))

small_vars_plasma = full_join(snv_plasma, indel_plasma) %>%
					full_join(healthy_snv) %>%
					full_join(healthy_indel)
small_vars_plasma = small_vars_plasma %>%
  					mutate(subj_type = ifelse(subj_type == "Healthy", "Control", subj_type))
  					
small_vars_plasma = small_vars_plasma %>%
					mutate(loc = str_c(chrom, ":", position_orig, "_", ref_orig, ">", alt_orig))  					

variants = label_bio_source(small_vars_plasma)

variants = left_join(variants, msk_anno %>% dplyr::select(patient_id, chrom, position, ref, alt, CASE:complex_indel_duplicate))
variants = variants %>%
		   mutate(bio_source = case_when(
		   					   MSK == 1 & grail == 1 ~ "biopsy_matched",
		   					   MSK == 1 & grail == 0 ~ "biopsy_only",
		   					   category %in% c("artifact", "edge", "low_depth", "low_qual") ~ "noise",
		   					   category %in% c("germline", "germlineish") ~ "germline",
		   					   category %in% c("blood", "bloodier") ~ "WBC_matched",
		   					   category == "somatic" & `IM-T.alt_count` > bam_read_count_cutoff ~ "IMPACT-BAM_matched",
		   					   category == "somatic" ~ "VUSo",
		   					   TRUE ~ "other"),
		   		  af = ifelse(is.na(af), 0, af),
		   		  af_nobaq = round(adnobaq / dpnobaq * 100, 2),
		   		  af_nobaq = ifelse(is.na(af_nobaq), 0, af_nobaq))

variants = variants %>%
		   filter(is_nonsyn) %>%
 		   filter(bio_source %in% c("VUSo", "biopsy_matched")) %>%
 		   filter(patient_id %in% c(msi_hypermutators$patient_id, hypermutators$patient_id))
 		   
mutation_summary = data.frame(variants[,c("patient_id", "chrom", "position", "ref_orig", "alt_orig"),drop=FALSE])
colnames(mutation_summary) = c("Sample", "CHROM", "POS", "REF", "ALT")
mutation_summary = cbind(mutation_summary, "Type"=rep("SNV", nrow(mutation_summary)))
vcf = preprocessInput_snv(input_data = mutation_summary,
                          ensgene = ensgene,
                          reference_genome = ref_genome)
patient_ids = unique(vcf$Sample)
res = foreach (i=1:length(patient_ids)) %dopar% {
 	cat(i, "of", length(patient_ids), "\n")
 	vcf = vcf %>%
		  filter(Sample == patient_ids[i])
	plot_96_spectrum(vcf, sample.col = "Sample",  file = paste0("../res/figureS6/", patient_ids[i], ".pdf"))
	return(1)
}

export_x = vcf %>%
		   filter(`Type`=="SNV") %>%
		   mutate(tissue = case_when(grepl("VB", Sample) ~ "Breast",
			   				 		 grepl("VL", Sample) ~ "Lung",
			   				 		 grepl("VP", Sample) ~ "Prostate")) %>%
		   dplyr::select(`patient_id` = `Sample`,
		   				 `tissue`,
		   				 `chromosome` = `CHROM`,
		   				 `position` = `POS`,
		   				 `reference_allele` = `REF`,
		   				 `alternate_allele` = `ALT`,
		   				 `context3`,
		   				 `mutcat3`,
		   				 `context5`,
		   				 `mutcat5`) %>%
		   filter(nchar(reference_allele)==1 & nchar(alternate_allele)==1)
write_tsv(export_x, path="../res/etc/Source_Data_Extended_Data_Fig_5/Extended_Data_Fig_5f.tsv", append=FALSE, col_names=TRUE)
