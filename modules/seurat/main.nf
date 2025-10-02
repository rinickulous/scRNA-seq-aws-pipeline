process SEURAT_ANALYSIS {
    tag "$meta.id"
    label 'process_medium'
    
    container 'satijalab/seurat:5.0.0'
    
    input:
    tuple val(meta), path(matrix_dir)
    
    output:
    tuple val(meta), path("${prefix}_seurat.rds")      , emit: seurat_object
    tuple val(meta), path("${prefix}_qc_plots.pdf")    , emit: qc_plots
    tuple val(meta), path("${prefix}_umap.pdf")        , emit: umap
    tuple val(meta), path("${prefix}_markers.csv")     , emit: markers
    tuple val(meta), path("${prefix}_metadata.csv")    , emit: metadata
    path "versions.yml"                                , emit: versions
    
    when:
    task.ext.when == null || task.ext.when
    
    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    
    library(Seurat)
    library(ggplot2)
    library(dplyr)
    
    # Read 10x data
    counts <- Read10X(data.dir = "${matrix_dir}")
    
    # Create Seurat object
    seurat_obj <- CreateSeuratObject(
        counts = counts,
        project = "${meta.id}",
        min.cells = 3,
        min.features = 200
    )
    
    # Calculate mitochondrial percentage
    seurat_obj[["percent.mt"]] <- PercentageFeatureSet(seurat_obj, pattern = "^MT-")
    
    # QC plots
    pdf("${prefix}_qc_plots.pdf", width = 12, height = 8)
    VlnPlot(seurat_obj, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"), ncol = 3)
    plot1 <- FeatureScatter(seurat_obj, feature1 = "nCount_RNA", feature2 = "percent.mt")
    plot2 <- FeatureScatter(seurat_obj, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")
    print(plot1 + plot2)
    dev.off()
    
    # Filter cells
    seurat_obj <- subset(seurat_obj, subset = nFeature_RNA > 200 & nFeature_RNA < 2500 & percent.mt < 5)
    
    # Normalize data
    seurat_obj <- NormalizeData(seurat_obj)
    seurat_obj <- FindVariableFeatures(seurat_obj, selection.method = "vst", nfeatures = 2000)
    
    # Scale and run PCA
    all.genes <- rownames(seurat_obj)
    seurat_obj <- ScaleData(seurat_obj, features = all.genes)
    seurat_obj <- RunPCA(seurat_obj, features = VariableFeatures(object = seurat_obj))
    
    # Cluster cells
    seurat_obj <- FindNeighbors(seurat_obj, dims = 1:10)
    seurat_obj <- FindClusters(seurat_obj, resolution = 0.5)
    
    # Run UMAP
    seurat_obj <- RunUMAP(seurat_obj, dims = 1:10)
    
    # Plot UMAP
    pdf("${prefix}_umap.pdf", width = 10, height = 8)
    DimPlot(seurat_obj, reduction = "umap", label = TRUE)
    dev.off()
    
    # Find markers for all clusters
    markers <- FindAllMarkers(seurat_obj, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.25)
    write.csv(markers, file = "${prefix}_markers.csv", row.names = FALSE)
    
    # Save metadata
    write.csv(seurat_obj@meta.data, file = "${prefix}_metadata.csv")
    
    # Save Seurat object
    saveRDS(seurat_obj, file = "${prefix}_seurat.rds")
    
    # Version info
    writeLines(
        paste0('"${task.process}":\n    seurat: ', packageVersion('Seurat')),
        "versions.yml"
    )
    """
}