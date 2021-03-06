
# Set up environment
path <- "/Users/Alex/Desktop/"
path2 <- "/Users/Alex/"

library(ggplot2)
library(cowplot)
library(reshape2)
library(ggrepel)
library(raster)

zscore <- function(counts){
  z <- (counts - sum(counts)) / sd(counts)
  return(z)
}

# Sample data
metadata <- read.csv(file = paste(path2, "Desktop/geodes/bioinformatics_workflow/R_processing/sample_metadata.csv", sep = ""), header = T)


mnorm <- read.csv(paste(path, "geodes_data_tables/Mendota_ID90_normalized_readcounts.csv", sep = ""), header = T, row.names = 1)
mnorm <- mnorm[, which(colnames(mnorm) != "GEODES158.nonrRNA")]
colnames(mnorm) <- gsub(".nonrRNA", "", colnames(mnorm))
mendota_key <- read.csv(paste(path, "geodes_data_tables/Mendota_ID90_genekey_geneclassifications_2018-11-28.csv", sep = ""), header = T)


tnorm <- read.csv(paste(path, "geodes_data_tables/Trout_ID90_normalized_readcounts.csv", sep = ""), header = T, row.names = 1)
tnorm <- tnorm[, which(colnames(tnorm) != "GEODES065.nonrRNA")]
colnames(tnorm) <- gsub(".nonrRNA", "", colnames(tnorm))
trout_key <- read.csv(paste(path, "geodes_data_tables/Trout_ID90_genekey_geneclassifications_2018-11-28.csv", sep = ""), header = T)


snorm <- read.csv(paste(path, "geodes_data_tables/Sparkling_ID90_normalized_readcounts.csv", sep = ""), header = T, row.names = 1)
snorm <- snorm[, which(colnames(snorm) != "GEODES014.nonrRNA" & colnames(snorm) != "GEODES033.nonrRNA")]
colnames(snorm) <- gsub(".nonrRNA", "", colnames(snorm))
spark_key <- read.csv(paste(path, "geodes_data_tables/Sparkling_ID90_genekey_geneclassifications_2018-11-28.csv", sep = ""), header = T)


# Metagenome data
metaG_reads <- read.table(paste(path, "geodes_data_tables/GEODES_metaG_ID90_2018-03-10.readcounts.txt", sep = ""), row.names = 1, sep = "\t")
colnames(metaG_reads) <- c("GEODES005", "GEODES006", "GEODES057", "GEODES058", "GEODES117", "GEODES118", "GEODES165", "GEODES166", "GEODES167", "GEODES168")
metaG_key <- read.table(paste(path, "geodes_data_tables/GEODES_metaG_genekey_2018-03-12.txt", sep = ""), sep = "\t", quote = "")
colnames(metaG_key) <- c("Gene", "Genome", "Taxonomy", "Product")
lakekey <- c("Sparkling", "Sparkling", "Trout", "Trout", "Mendota", "Mendota", "Sparkling2009", "Sparkling2009", "Sparkling2009", "Sparkling2009")
metaG_reads <- sweep(metaG_reads, 2, colSums(metaG_reads), "/")

# Add phylum info to keys
# Process metagenome gene key to include a phylum column. Fix any weird formats.

# metaG_key$Taxonomy <- gsub("Bacteria;", "", metaG_key$Taxonomy)
# metaG_key$Taxonomy <- gsub("Eukaryota;", "", metaG_key$Taxonomy)
# metaG_key$Taxonomy <- gsub("Proteobacteria;", "", metaG_key$Taxonomy)
# metaG_key$Phylum <- sapply(strsplit(as.character(metaG_key$Taxonomy),";"), `[`, 1)
# 
# metaG_key$Phylum <- gsub("Cryptophyta,Cryptophyceae,Pyrenomonadales,Geminigeraceae,Guillardia,theta", "Cryptophyta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Haptophyta,Prymnesiophyceae,Isochrysidales,Noelaerhabdaceae,Emiliania,huxleyi", "Haptophyta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Heterokonta,Coscinodiscophyceae,Thalassiosirales,Thalassiosiraceae,Thalassiosira,pseudonana", "Heterokonta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Heterokonta,Pelagophyceae,Pelagomonadales,Pelagomonadaceae,Aureococcus,anophagefferens", "Heterokonta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Heterokonta,Ochrophyta,Eustigmataphyceae,Eustigmataceae,Nannochloropsis,gaditana", "Heterokonta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Heterokonta,Bacillariophyceae,Naviculales,Phaeodactylaceae,Phaeodactylum,tricornutum", "Heterokonta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified unclassified unclassified unclassified unclassified", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified unclassified unclassified unclassified", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified unclassified unclassified", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("NO CLASSIFICATION MH", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("NO CLASSIFICATION LP", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("NO CLASSIFICATION DUE TO FEW HITS IN PHYLODIST", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("NO CLASSIFICATION BASED ON GIVEN PHYLODIST", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("None", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified unclassified Perkinsida", "Perkinsozoa", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified unclassified", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified Oligohymenophorea", "Ciliophora", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified Pelagophyceae", "Ochrophyta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("unclassified", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Unclassified ", "Unclassified", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("UnclassifiedIsochrysidales", "Haptophyta", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("TM7", "Saccharibacteria", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Ignavibacteriae", "Ignavibacteria", metaG_key$Phylum)
# metaG_key$Phylum <- gsub("Crenarchaeaota", "Crenarchaeota", metaG_key$Phylum)
# metaG_key$Phylum[which(is.na(metaG_key$Phylum) == T)] <- "Unclassified"
# metaG_key$Phylum[grep("Blank", metaG_key$Phylum)] <- "Unclassified"
# 
# # Remove unclassified genes to save on RAM
# metaG_key <- metaG_key[which(metaG_key$Phylum != "Unclassified"),]
# 
# # Split metagenome read count tables by lake and prep for melting
# metaG_reads$Genes <- rownames(metaG_reads)
# metaG_reads <- metaG_reads[match(metaG_reads$Genes, metaG_key$Gene),]
# spark_metaG <- metaG_reads[,c(1,2, 11)]
# trout_metaG <- metaG_reads[,c(3,4, 11)]
# mendota_metaG <- metaG_reads[,c(5,6, 11)]
# 
# # Use melt to switch from wide to long format
# spark_metaG <- melt(spark_metaG)
# trout_metaG <- melt(trout_metaG)
# mendota_metaG <- melt(mendota_metaG)
# 
# # Add phylum column to each melted lake table
# mendota_metaG$Phylum <- metaG_key$Phylum[match(mendota_metaG$Genes, metaG_key$Gene)]
# trout_metaG$Phylum <- metaG_key$Phylum[match(trout_metaG$Genes, metaG_key$Gene)]
# spark_metaG$Phylum <- metaG_key$Phylum[match(spark_metaG$Genes, metaG_key$Gene)]
# 
# # Aggregate counts by phylum
# mendota_metaG_phyla <- aggregate(value ~ Phylum, data = mendota_metaG, sum)
# spark_metaG_phyla <- aggregate(value ~ Phylum, data = spark_metaG, sum)
# trout_metaG_phyla <- aggregate(value ~ Phylum, data = trout_metaG, sum)
# 
# # Write these datasets to file so that I can load them instead of rerunning all of the above when I need to make plot modifications
# write.csv(mendota_metaG_phyla, file = paste(path2, "Desktop/intermediate_plotting_files/mendota_metaG_phyla.csv", sep = ""), quote = F, row.names = F)
# write.csv(spark_metaG_phyla, file = paste(path2, "Desktop/intermediate_plotting_files/spark_metaG_phyla.csv", sep = ""), quote = F, row.names = F)
# write.csv(trout_metaG_phyla, file = paste(path2, "Desktop/intermediate_plotting_files/trout_metaG_phyla.csv", sep = ""), quote = F, row.names = F)
# 
# # Remove some files so I have space in RAM to run the next steps
# rm(metaG_key)
# rm(metaG_reads)
# rm(mendota_metaG)
# rm(spark_metaG)
# rm(trout_metaG)

mendota_metaG_phyla <- read.csv(file = paste(path2, "Desktop/intermediate_plotting_files/mendota_metaG_phyla.csv", sep = ""), header = T, colClasses = c("character", "numeric"))
spark_metaG_phyla <- read.csv(file = paste(path2, "Desktop/intermediate_plotting_files/spark_metaG_phyla.csv", sep = ""), header = T, colClasses = c("character", "numeric"))
trout_metaG_phyla <- read.csv(file = paste(path2, "Desktop/intermediate_plotting_files/trout_metaG_phyla.csv", sep = ""), header = T, colClasses = c("character", "numeric"))
# # 
# # 
# # # Include a key for colorcoding phyla by broader classification
# # 
type_key <- data.frame(phylum = c("Actinobacteria", "Bacteroidetes", "Chloroflexi", "Crenarchaeota", "Cryptophyta", "Cyanobacteria", "Gemmatimonadetes", "Heterokonta", "Ignavibacteria", "Planctomycetes", "Alphaproteobacteria", "Verrucomicrobia", "Viruses", "Armatimonadetes", "Firmicutes", "Ciliophora", "Acidobacteria", "Tenericutes", "Arthropoda", "Chlorobi", "Candidatus Saccharibacteria", "Chlorophyta", "Deinococcus-Thermus", "Elusimicrobia", "Haptophyta", "Spirochaetes", "Phaeophyceae", "Streptophyta", "Betaproteobacteria", "Deltaproteobacteria", "Gammaproteobacteria", "Epsilonproteobacteria", "Fibrobacteres", "Marinimicrobia", "Oligoflexia"), type = c("Bacteria", "Bacteria", "Bacteria", "Archaea", "Algae", "Bacteria", "Bacteria", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Viruses", "Bacteria", "Bacteria", "Protist", "Bacteria", "Bacteria", "Animal", "Bacteria", "Bacteria", "Algae", "Bacteria", "Bacteria", "Algae", "Bacteria", "Algae", "Algae", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria", "Bacteria"))
# 
# 
# #Process Mendota expression data
# 
# 
# # Remove unclassified genes and the internal standard
# mendota_key <- mendota_key[grep("Unclassified|internal standard", mendota_key$Phylum, invert = T), ]
# 
# # Prep read count table and switch to long format
# mnorm2 <- mnorm
# mnorm2$Genes <- rownames(mnorm2)
# mnorm2 <- mnorm2[which(mnorm2$Genes %in% mendota_key$Gene), ]
# colnames(mnorm2) <- gsub(".nonrRNA", "", colnames(mnorm2))
# mnorm2 <- melt(mnorm2)
# # Add columns of timepoint and phylum
# mnorm2$Timepoint <- metadata$Timepoint[match(mnorm2$variable, metadata$Sample)]
# mnorm2$Taxonomy <- mendota_key$Phylum[match(mnorm2$Genes, mendota_key$Gene)]
# 
# # Aggregate by phylum
# mendota_phyla <- aggregate(value ~ Taxonomy, data = mnorm2, sum)
# mendota_total <- sum(colSums(mnorm))
# mendota_phyla$value <- mendota_phyla$value/mendota_total
# 
# # Save an intermediate file of Mendota data
# write.csv(mendota_phyla, file = paste(path2, "Desktop/intermediate_plotting_files/mendota_metaT_phyla.csv", sep = ""), quote = F, row.names = F)
# Read back in
mendota_phyla <- read.csv(file = paste(path2, "Desktop/intermediate_plotting_files/mendota_metaT_phyla.csv", sep = ""), header = T, colClasses = c("character", "numeric"))

# Keep the top half of both expressed and abundant phyla for plotting
# keep_phyla <- c(mendota_metaG_phyla$Phylum[which(mendota_metaG_phyla$value > quantile(mendota_metaG_phyla$value)[3])], mendota_phyla$Taxonomy[which(mendota_phyla$value > quantile(mendota_phyla$value)[3])])
# mendota_phyla <- mendota_phyla[which(mendota_phyla$Taxonomy %in% keep_phyla),]
mendota_phyla$metaG <- mendota_metaG_phyla$value[match(mendota_phyla$Taxonomy, mendota_metaG_phyla$Phylum)]
mendota_phyla$type <- type_key$type[match(mendota_phyla$Taxonomy, type_key$phylum)]
mendota_phyla <- mendota_phyla[which(is.na(mendota_phyla$metaG) == F),]



# Color key: c("limegreen", "lavenderblush4", "royalblue", "goldenrod")) == algae, archaea, bacteria, viruses
p1 <- ggplot(mendota_phyla, aes(x = metaG, y = value, color = type)) + geom_point(size = 2.5, alpha = 0.5) + geom_text_repel(aes(label = Taxonomy), force = 10, size = 3, color = "black", segment.alpha = 0.25, box.padding = 0.5, point.padding = 0.5, data = subset(mendota_phyla, metaG > 0.0000007 | value > 0.025), nudge_y = 0.0015, ylim = c(0.025, NA)) + labs(x = "Metagenomic reads", y = "Metatranscriptomic reads", title = "A. Lake Mendota") + theme(legend.position = "none") + scale_x_continuous(limits = c(0, max(mendota_phyla$metaG)), labels = scales::scientific) + background_grid(major = "xy", minor = "xy") + scale_y_continuous(labels = scales::scientific) + scale_color_manual(values = c("limegreen",  "royalblue", "goldenrod"))


#Process Sparkling expression data

# Remove unclassified genes and the internal standard
 spark_key <- spark_key[grep("Unclassified|internal standard", spark_key$Phylum, invert = T), ]

# # Prep read count table and switch to long format
# snorm2 <- snorm
# snorm2$Genes <- rownames(snorm2)
# snorm2 <- snorm2[which(snorm2$Genes %in% spark_key$Gene), ]
# colnames(snorm2) <- gsub(".nonrRNA", "", colnames(snorm2))
# snorm2 <- melt(snorm2)
# # Add columns of timepoint and phylum
# snorm2$Timepoint <- metadata$Timepoint[match(snorm2$variable, metadata$Sample)]
# snorm2$Taxonomy <- spark_key$Phylum[match(snorm2$Genes, spark_key$Gene)]
# 
# #Aggregate by phylum
# spark_phyla <- aggregate(value ~ Taxonomy, data = snorm2, sum)
# spark_total <- sum(colSums(snorm))
# spark_phyla$value <- spark_phyla$value/spark_total
# 
# #Save an intermediate file of Mendota data
# write.csv(spark_phyla, file = paste(path2, "Desktop/intermediate_plotting_files/spark_metaT_phyla.csv", sep = ""), quote = F, row.names = F)
# Read back in
spark_phyla <- read.csv(file = paste(path2, "Desktop/intermediate_plotting_files/spark_metaT_phyla.csv", sep = ""), header = T, colClasses = c("character", "numeric"))


# Keep the top half of both expressed and abundant phyla for plotting
# keep_phyla <- c(spark_metaG_phyla$Phylum[which(spark_metaG_phyla$value > quantile(spark_metaG_phyla$value)[3])], spark_phyla$Taxonomy[which(spark_phyla$value > quantile(spark_phyla$value)[3])])
# spark_phyla <- spark_phyla[which(spark_phyla$Taxonomy %in% keep_phyla),]
spark_phyla$metaG <- spark_metaG_phyla$value[match(spark_phyla$Taxonomy, spark_metaG_phyla$Phylum)]
spark_phyla$type <- type_key$type[match(spark_phyla$Taxonomy, type_key$phylum)]
spark_phyla <- spark_phyla[which(is.na(spark_phyla$metaG) == F),]

p2 <- ggplot(spark_phyla, aes(x = metaG, y = value, color = type)) + geom_point(size = 2.5, alpha = 0.5) + geom_text_repel(aes(label = Taxonomy), force = 18, size = 3, color = "black", segment.alpha = 0.25, box.padding = 0.5,  data = subset(spark_phyla, metaG > 0.00000002 | value > 0.02), nudge_x = 0.0000001) + labs(x = "Metagenomic reads", y = "Metatranscriptomic reads", title = "B. Sparkling Lake") + theme(legend.position = "none") + scale_x_continuous(limits = c(0, max(spark_phyla$metaG)), labels = scales::scientific) + background_grid(major = "xy", minor = "none") + scale_y_continuous(labels = scales::scientific) + scale_color_manual(values = c("lightcoral", "limegreen", "royalblue", "goldenrod"))
#Process Trout expression data

# # Remove unclassified genes and the internal standard
trout_key <- trout_key[grep("Unclassified|internal standard", trout_key$Phylum, invert = T), ]

# #Prep read count table and switch to long format
# tnorm2 <- tnorm
# tnorm2$Genes <- rownames(tnorm2)
# tnorm2 <- tnorm2[which(tnorm2$Genes %in% trout_key$Gene), ]
# colnames(tnorm2) <- gsub(".nonrRNA", "", colnames(tnorm2))
# tnorm2 <- melt(tnorm2)
# # Add columns of timepoint and phylum
# tnorm2$Timepoint <- metadata$Timepoint[match(tnorm2$variable, metadata$Sample)]
# tnorm2$Taxonomy <- trout_key$Phylum[match(tnorm2$Genes, trout_key$Gene)]
# 
# # Aggregate by phylum
# trout_phyla <- aggregate(value ~ Taxonomy, data = tnorm2, sum)
# trout_total <- sum(colSums(tnorm))
# trout_phyla$value <- trout_phyla$value/trout_total
# 
# # Save an intermediate file of Mendota data
# write.csv(trout_phyla, file = paste(path2, "Desktop/intermediate_plotting_files/trout_metaT_phyla.csv", sep = ""), quote = F, row.names = F)
#Read back in
trout_phyla <- read.csv(file = paste(path2, "Desktop/intermediate_plotting_files/trout_metaT_phyla.csv", sep = ""), header = T, colClasses = c("character", "numeric"))

# Keep the top half of both expressed and abundant phyla for plotting
# keep_phyla <- c(trout_metaG_phyla$Phylum[which(trout_metaG_phyla$value > quantile(trout_metaG_phyla$value)[3])], trout_phyla$Taxonomy[which(trout_phyla$value > quantile(trout_phyla$value)[3])])
# trout_phyla <- trout_phyla[which(trout_phyla$Taxonomy %in% keep_phyla),]
trout_phyla$metaG <- trout_metaG_phyla$value[match(trout_phyla$Taxonomy, trout_metaG_phyla$Phylum)]
trout_phyla$type <- type_key$type[match(trout_phyla$Taxonomy, type_key$phylum)]
trout_phyla <- trout_phyla[which(is.na(trout_phyla$metaG) == F),]

p3 <- ggplot(trout_phyla, aes(x = metaG, y = value, color = type)) + geom_point(size = 2.5, alpha = 0.5) + geom_text_repel(aes(label = Taxonomy), force = 15, size = 3, color = "black", segment.alpha = 0.25, box.padding = 0.5, data = subset(trout_phyla, metaG > 0.00000000015 | value > 0.01)) + labs(x = "Metagenomic reads", y = "Metatranscriptomic reads", title = "C. Trout Bog") + theme(legend.position = "none") + scale_x_continuous(limits = c(0, max(trout_phyla$metaG)), labels = scales::scientific) + background_grid(major = "xy", minor = "none") + scale_y_continuous(labels = scales::scientific) + scale_color_manual(values = c("lightcoral", "limegreen", "royalblue", "goldenrod"))

#e my various gene keys into just genes with tribe classifications
metaG_key$Taxonomy <- gsub("Bacteria;", "", metaG_key$Taxonomy)
metaG_key$Clade <- sapply(strsplit(as.character(metaG_key$Taxonomy),";"), `[`, 5)
metaG_key$Clade[which(metaG_key$Clade == "Candidatus Methylopumilus")] <- "betIV-A"
metaG_key$Clade[which(metaG_key$Clade == "Polynucleobacter")] <- "Pnec"
metaG_key$Clade[which(metaG_key$Clade == "Algoriphagus")] <- "bacIII-B"
metaG_key$Clade[which(metaG_key$Clade == "Anabaena")] <- "AnaI-A"
metaG_key$Clade[which(metaG_key$Clade == "Aquiluna")] <- "LunaI-A"
metaG_key$Clade[which(metaG_key$Clade == "Curvibacter")] <- "Lhab-A"
metaG_key$Clade[which(metaG_key$Clade == "Haliscomenobacter")] <- "bacIV-A"
metaG_key$Clade[which(metaG_key$Clade == "Herbaspirillum")] <- "betVII-B"
metaG_key$Clade[which(metaG_key$Clade == "Limnohabitans")] <- "Lhab-A"
metaG_key$Clade[which(metaG_key$Clade == "Mycobacterium")] <- "acTH2-A"
metaG_key$Clade[which(metaG_key$Clade == "Novosphingobium")] <- "alfIV-A"
metaG_key$Clade[which(metaG_key$Clade == "Pedobacter")] <- "bacVI-B"
metaG_key$Clade[which(metaG_key$Clade == "Rhodoluna")] <- "LunaI-A"
metaG_key$Clade[which(metaG_key$Clade == "Sphingopyxis")] <- "alfIV-B"
metaG_key$Clade[which(metaG_key$Clade == "LD28")] <- "betIV-A"

# Aggregate the metagenomic reads

metaG_key2 <- metaG_key[which(is.na(metaG_key$Clade) == FALSE),]
metaG_reads2 <- metaG_reads

# Split metagenome read count tables by lake and prep for melting
metaG_reads2$Genes <- rownames(metaG_reads2)
metaG_reads2 <- metaG_reads2[match(metaG_reads2$Genes, metaG_key2$Gene),]
spark_metaG <- metaG_reads2[,c(1,2, 11)]
trout_metaG <- metaG_reads2[,c(3,4, 11)]
mendota_metaG <- metaG_reads2[,c(5,6, 11)]

# Use melt to switch from wide to long format
spark_metaG <- melt(spark_metaG)
trout_metaG <- melt(trout_metaG)
mendota_metaG <- melt(mendota_metaG)

# Add phylum column to each melted lake table
mendota_metaG$Clade <- metaG_key2$Clade[match(mendota_metaG$Genes, metaG_key2$Gene)]
trout_metaG$Clade <- metaG_key2$Clade[match(trout_metaG$Genes, metaG_key2$Gene)]
spark_metaG$Clade <- metaG_key2$Clade[match(spark_metaG$Genes, metaG_key2$Gene)]

# Aggregate counts by Clade
mendota_metaG_Clade <- aggregate(value ~ Clade, data = mendota_metaG, sum)
spark_metaG_Clade <- aggregate(value ~ Clade, data = spark_metaG, sum)
trout_metaG_Clade <- aggregate(value ~ Clade, data = trout_metaG, sum)

#Now to add in the gene expression
mendota_key$Taxonomy <- gsub("Bacteria;", "", mendota_key$Taxonomy)
mendota_key$Clade <- sapply(strsplit(as.character(mendota_key$Taxonomy),";"), `[`, 5)

mnorm2 <- mnorm
mnorm2$Genes <- rownames(mnorm2)
mnorm2 <- mnorm2[which(mnorm2$Genes %in% mendota_key$Gene), ]
#colnames(mnorm2) <- gsub(".nonrRNA", "", colnames(mnorm2))
mnorm2 <- melt(mnorm2)
# Add columns of timepoint and phylum
#mnorm2$Timepoint <- metadata$Timepoint[match(mnorm2$variable, metadata$Sample)]
mnorm2$Taxonomy <- mendota_key$Clade[match(mnorm2$Genes, mendota_key$Gene)]

# Make some modifications to names before aggregating
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "PnecC" | mnorm2$Taxonomy == "Polynucleobacter necessarius")] <- "Pnec"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Candidatus Methylopumilus planktonicus" | mnorm2$Taxonomy == "Candidatus Methylopumilus turicensis")] <- "betIV-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Lhab-A1" | mnorm2$Taxonomy == "Limnohabitans sp. Rim28")] <- "Lhab-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Novosphingobium sp. AAP93")] <- "alfIV-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Algoriphagus")] <- "bacIII-B"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Anabaena")] <- "AnaI-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Aquiluna")] <- "LunaI-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Curvibacter pauculus" | mnorm2$Taxonomy == "Curvibacter gracilis" | mnorm2$Taxonomy == "Curvibacter lanceolatus" | mnorm2$Taxonomy == "Curvibacter sp. PAE-UM")] <- "Lhab-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Haliscomenobacter")] <- "bacIV-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Herbaspirillum frisingense" | mnorm2$Taxonomy == "Herbaspirillum huttiense" | mnorm2$Taxonomy == "Herbaspirillum sp. B39")] <- "betVII-B"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Mycobacterium")] <- "acTH2-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Novosphingobium")] <- "alfIV-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Pedobacter")] <- "bacVI-B"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Rhodoluna")] <- "LunaI-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Luna1-A")] <- "LunaI-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "Sphingopyxis")] <- "alfIV-B"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "LD28")] <- "betIV-A"
mnorm2$Taxonomy[which(mnorm2$Taxonomy == "LD12")] <- "alfV-A"

# Aggregate by phylum
mendota_clade <- aggregate(value ~ Taxonomy, data = mnorm2, sum)
mendota_total <- sum(colSums(mnorm))
mendota_clade$value <- mendota_clade$value/mendota_total
mendota_clade <- mendota_clade[which(mendota_clade$Taxonomy != ""), ]
mendota_clade <- mendota_clade[grep("unclassified", mendota_clade$Taxonomy, invert = T), ]



mendota_clade$metaG <- mendota_metaG_Clade$value[match(mendota_clade$Taxonomy, mendota_metaG_Clade$Clade)]
mendota_clade <- mendota_clade[which(is.na(mendota_clade$metaG) == F),]
mendota_clade <- mendota_clade[grep("-|Pnec", mendota_clade$Taxonomy), ]

phyla <- rep("Other", dim(mendota_clade)[1])
phyla[which(mendota_clade$Taxonomy == "acI-A" | mendota_clade$Taxonomy == "acI-B" | mendota_clade$Taxonomy == "acTH2-A" | mendota_clade$Taxonomy == "acIV-A"| mendota_clade$Taxonomy == "acIV-B" | mendota_clade$Taxonomy == "acSTL-A" | mendota_clade$Taxonomy == "acTH1-A" | mendota_clade$Taxonomy == "LunaI-A")] <- "Actinobacteria"
phyla[which(mendota_clade$Taxonomy == "betIV-A" | mendota_clade$Taxonomy == "betVII-B" | mendota_clade$Taxonomy == "betIV-A" | mendota_clade$Taxonomy == "Lhab-A" | mendota_clade$Taxonomy == "Pnec")] <- "Betaproteobacteria"
phyla[which(mendota_clade$Taxonomy == "alfV-A" | mendota_clade$Taxonomy == "alfIV-A")] <- "Alphaproteobacteria"
phyla[which(mendota_clade$Taxonomy == "bacIII-B" | mendota_clade$Taxonomy == "bacI-A" | mendota_clade$Taxonomy == "bacII-A" | mendota_clade$Taxonomy == "bacIV-A" | mendota_clade$Taxonomy == "bacVI-B")] <- "Bacteroides"
phyla[which(mendota_clade$Taxonomy == "AnaI-A")] <- "Cyanobacteria"
phyla[which(mendota_clade$Taxonomy == "verI-B")] <- "Verrucomicrobia"
mendota_clade$phyla <- phyla

# Color key: c("limegreen", "lavenderblush4", "royalblue", "goldenrod")) == algae, archaea, bacteria, viruses
p4 <- ggplot(mendota_clade, aes(x = metaG, y = value, color = phyla)) + geom_point(size = 2.5, alpha = 0.5) + geom_text_repel(aes(label = Taxonomy), force = 15, size = 3, color = "black", segment.alpha = 0.25, box.padding = 0.5, data = subset(mendota_clade, metaG > 0.005 | value > 0.001)) + labs(x = "Metagenomic reads", y = "Metatranscriptomic reads", title = "D. Lake Mendota") + theme(legend.position = "none") + scale_x_continuous(limits = c(0, max(mendota_clade$metaG)), labels = scales::scientific) + background_grid(major = "xy", minor = "xy") + scale_y_continuous(labels = scales::scientific)  + scale_color_manual(values = c("firebrick2", "skyblue2", "goldenrod", "dodgerblue", "green", "purple"))

# Repeat with Trout

trout_key$Taxonomy <- gsub("Bacteria;", "", trout_key$Taxonomy)
trout_key$Clade <- sapply(strsplit(as.character(trout_key$Taxonomy),";"), `[`, 5)

tnorm2 <- tnorm
tnorm2$Genes <- rownames(tnorm2)
tnorm2 <- tnorm2[which(tnorm2$Genes %in% trout_key$Gene), ]
#colnames(tnorm2) <- gsub(".nonrRNA", "", colnames(tnorm2))
tnorm2 <- melt(tnorm2)
# Add columns of timepoint and phylum
#tnorm2$Timepoint <- metadata$Timepoint[match(tnorm2$variable, metadata$Sample)]
tnorm2$Taxonomy <- trout_key$Clade[match(tnorm2$Genes, trout_key$Gene)]

# Make some modifications to names before aggregating
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "PnecC" | tnorm2$Taxonomy == "Polynucleobacter necessarius")] <- "Pnec"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Candidatus Methylopumilus planktonicus" | tnorm2$Taxonomy == "Candidatus Methylopumilus turicensis")] <- "betIV-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Lhab-A1" | tnorm2$Taxonomy == "Limnohabitans sp. Rim28")] <- "Lhab-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Novosphingobium sp. AAP93")] <- "alfIV-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Algoriphagus")] <- "bacIII-B"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Anabaena")] <- "AnaI-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Aquiluna")] <- "LunaI-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Curvibacter pauculus" | tnorm2$Taxonomy == "Curvibacter gracilis" | tnorm2$Taxonomy == "Curvibacter lanceolatus" | tnorm2$Taxonomy == "Curvibacter sp. PAE-UM")] <- "Lhab-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Haliscomenobacter")] <- "bacIV-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Herbaspirillum frisingense" | tnorm2$Taxonomy == "Herbaspirillum huttiense" | tnorm2$Taxonomy == "Herbaspirillum sp. B39")] <- "betVII-B"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Mycobacterium")] <- "acTH2-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Novosphingobium")] <- "alfIV-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Pedobacter")] <- "bacVI-B"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Rhodoluna")] <- "LunaI-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "Sphingopyxis")] <- "alfIV-B"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "LD28")] <- "betIV-A"
tnorm2$Taxonomy[which(tnorm2$Taxonomy == "LD12")] <- "alfV-A"

# Aggregate by phylum
trout_clade <- aggregate(value ~ Taxonomy, data = tnorm2, sum)
trout_total <- sum(colSums(tnorm))
trout_clade$value <- trout_clade$value/trout_total
trout_clade <- trout_clade[which(trout_clade$Taxonomy != ""), ]
trout_clade <- trout_clade[grep("unclassified", trout_clade$Taxonomy, invert = T), ]



trout_clade$metaG <- trout_metaG_Clade$value[match(trout_clade$Taxonomy, trout_metaG_Clade$Clade)]
trout_clade <- trout_clade[which(is.na(trout_clade$metaG) == F),]
trout_clade <- trout_clade[grep("-|Pnec", trout_clade$Taxonomy), ]

phyla <- rep("Other", dim(trout_clade)[1])
phyla[which(trout_clade$Taxonomy == "acI-A" | trout_clade$Taxonomy == "acI-B" | trout_clade$Taxonomy == "acTH2-A" | trout_clade$Taxonomy == "acIV-A"| trout_clade$Taxonomy == "acIV-B" | trout_clade$Taxonomy == "acSTL-A" | trout_clade$Taxonomy == "acTH1-A" | trout_clade$Taxonomy == "LunaI-A")] <- "Actinobacteria"
phyla[which(trout_clade$Taxonomy == "betIV-A" | trout_clade$Taxonomy == "betVII-B" | trout_clade$Taxonomy == "betIV-A" | trout_clade$Taxonomy == "Lhab-A" | trout_clade$Taxonomy == "Pnec")] <- "Betaproteobacteria"
phyla[which(trout_clade$Taxonomy == "alfV-A" | trout_clade$Taxonomy == "alfIV-A")] <- "Alphaproteobacteria"
phyla[which(trout_clade$Taxonomy == "bacIII-B" | trout_clade$Taxonomy == "bacI-A" | trout_clade$Taxonomy == "bacII-A" | trout_clade$Taxonomy == "bacIV-A" | trout_clade$Taxonomy == "bacVI-B")] <- "Bacteroides"
phyla[which(trout_clade$Taxonomy == "AnaI-A")] <- "Cyanobacteria"
phyla[which(trout_clade$Taxonomy == "verI-B")] <- "Verrucomicrobia"
trout_clade$phyla <- phyla

# Color key: c("limegreen", "lavenderblush4", "royalblue", "goldenrod")) == algae, archaea, bacteria, viruses
p5 <- ggplot(trout_clade[which(trout_clade$Taxonomy != "acI-B"),], aes(x = metaG, y = value, color = phyla)) + geom_point(size = 2.5, alpha = 0.5) + geom_text_repel(aes(label = Taxonomy), force = 15, size = 3, color = "black", segment.alpha = 0.25, box.padding = 0.5, data = subset(trout_clade[which(trout_clade$Taxonomy != "acI-B"),], value > 0.001 | metaG > 0.000003)) + labs(x = "Metagenomic reads", y = "Metatranscriptomic reads", title = "F. Trout Bog") + theme(legend.position = "none") + scale_x_continuous(limits = c(0, max(trout_clade$metaG)), labels = scales::scientific) + background_grid(major = "xy", minor = "xy") + scale_y_continuous(labels = scales::scientific) + scale_color_manual(values = c("firebrick2", "skyblue", "goldenrod", "dodgerblue", "green"))

# Repeat with Sparkling
spark_key$Taxonomy <- gsub("Bacteria;", "", spark_key$Taxonomy)
spark_key$Clade <- sapply(strsplit(as.character(spark_key$Taxonomy),";"), `[`, 5)

snorm2 <- snorm
snorm2$Genes <- rownames(snorm2)
snorm2 <- snorm2[which(snorm2$Genes %in% spark_key$Gene), ]
#colnames(snorm2) <- gsub(".nonrRNA", "", colnames(snorm2))
snorm2 <- melt(snorm2)
# Add columns of timepoint and phylum
#snorm2$Timepoint <- metadata$Timepoint[match(snorm2$variable, metadata$Sample)]
snorm2$Taxonomy <- spark_key$Clade[match(snorm2$Genes, spark_key$Gene)]

# Make some modifications to names before aggregating
snorm2$Taxonomy[which(snorm2$Taxonomy == "PnecC" | snorm2$Taxonomy == "Polynucleobacter necessarius")] <- "Pnec"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Candidatus Methylopumilus planktonicus" | snorm2$Taxonomy == "Candidatus Methylopumilus turicensis")] <- "betIV-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Lhab-A1" | snorm2$Taxonomy == "Limnohabitans sp. Rim28")] <- "Lhab-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Novosphingobium sp. AAP93")] <- "alfIV-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Algoriphagus")] <- "bacIII-B"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Anabaena")] <- "AnaI-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Aquiluna")] <- "LunaI-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Curvibacter pauculus" | snorm2$Taxonomy == "Curvibacter gracilis" | snorm2$Taxonomy == "Curvibacter lanceolatus" | snorm2$Taxonomy == "Curvibacter sp. PAE-UM")] <- "Lhab-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Haliscomenobacter")] <- "bacIV-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Herbaspirillum frisingense" | snorm2$Taxonomy == "Herbaspirillum huttiense" | snorm2$Taxonomy == "Herbaspirillum sp. B39")] <- "betVII-B"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Mycobacterium")] <- "acTH2-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Novosphingobium")] <- "alfIV-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Pedobacter")] <- "bacVI-B"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Rhodoluna")] <- "LunaI-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Luna1-A")] <- "LunaI-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "Sphingopyxis")] <- "alfIV-B"
snorm2$Taxonomy[which(snorm2$Taxonomy == "LD28")] <- "betIV-A"
snorm2$Taxonomy[which(snorm2$Taxonomy == "LD12")] <- "alfV-A"


# Aggregate by phylum
spark_clade <- aggregate(value ~ Taxonomy, data = snorm2, sum)
spark_total <- sum(colSums(snorm))
spark_clade$value <- spark_clade$value/spark_total
spark_clade <- spark_clade[which(spark_clade$Taxonomy != ""), ]
spark_clade <- spark_clade[grep("unclassified", spark_clade$Taxonomy, invert = T), ]



spark_clade$metaG <- spark_metaG_Clade$value[match(spark_clade$Taxonomy, spark_metaG_Clade$Clade)]
spark_clade <- spark_clade[which(is.na(spark_clade$metaG) == F),]
spark_clade <- spark_clade[grep("-|Pnec", spark_clade$Taxonomy), ]

phyla <- rep("Other", dim(spark_clade)[1])
phyla[which(spark_clade$Taxonomy == "acI-A" | spark_clade$Taxonomy == "acI-B" | spark_clade$Taxonomy == "acTH2-A" | spark_clade$Taxonomy == "acIV-A"| spark_clade$Taxonomy == "acIV-B" | spark_clade$Taxonomy == "acSTL-A" | spark_clade$Taxonomy == "acTH1-A" | spark_clade$Taxonomy == "LunaI-A")] <- "Actinobacteria"
phyla[which(spark_clade$Taxonomy == "betIV-A" | spark_clade$Taxonomy == "betVII-B" | spark_clade$Taxonomy == "betIV-A" | spark_clade$Taxonomy == "Lhab-A" | spark_clade$Taxonomy == "Pnec")] <- "Betaproteobacteria"
phyla[which(spark_clade$Taxonomy == "alfV-A" | spark_clade$Taxonomy == "alfIV-A")] <- "Alphaproteobacteria"
phyla[which(spark_clade$Taxonomy == "bacIII-B" | spark_clade$Taxonomy == "bacI-A" | spark_clade$Taxonomy == "bacII-A" | spark_clade$Taxonomy == "bacIV-A" | spark_clade$Taxonomy == "bacVI-B")] <- "Bacteroides"
phyla[which(spark_clade$Taxonomy == "AnaI-A")] <- "Cyanobacteria"
phyla[which(spark_clade$Taxonomy == "verI-B")] <- "Verrucomicrobia"
spark_clade$phyla <- phyla

# Color key: c("limegreen", "lavenderblush4", "royalblue", "goldenrod")) == algae, archaea, bacteria, viruses
p6 <- ggplot(spark_clade, aes(x = metaG, y = value, color = phyla)) + geom_point(size = 2.5, alpha = 0.5) + geom_text_repel(aes(label = Taxonomy), force = 15, size = 3, color = "black", segment.alpha = 0.25, box.padding = 0.5, data = subset(spark_clade, metaG > 0.001 | value > 0.0005), nudge_x = 0.001) + labs(x = "Metagenomic reads", y = "Metatranscriptomic reads", title = "E. Sparkling Lake") + theme(legend.position = "none") + scale_x_continuous(limits = c(0, max(spark_clade$metaG)), labels = scales::scientific) + background_grid(major = "xy", minor = "xy") + scale_y_continuous(labels = scales::scientific) + scale_color_manual(values = c("firebrick2", "skyblue2", "goldenrod", "dodgerblue", "green", "purple"))

to_plot <- plot_grid(p1, p2, p3, p4, p6, p5,  nrow = 2)

save_plot(paste(path,"geodes/Manuscript/figures_and_tables/abundance_vs_expression.pdf", sep = ""), to_plot, base_height = 8, base_aspect_ratio = 1.5)


