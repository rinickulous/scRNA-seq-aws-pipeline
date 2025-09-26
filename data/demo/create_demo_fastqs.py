import gzip

# Create R1 file (28bp reads - cell barcode + UMI)
with gzip.open("data/demo/demo_sample_R1_001.fastq.gz", "wt") as f:
    for i in range(1000):  # 1000 reads for quick demo
        f.write(f"@DEMO_READ_{i+1}_R1\n")
        f.write("AAACCTGAGAAGGCCTGTCAGATC\n")  # 24bp barcode
        f.write("+\n")
        f.write("IIIIIIIIIIIIIIIIIIIIIIII\n")

# Create R2 file (longer transcript reads)
with gzip.open("data/demo/demo_sample_R2_001.fastq.gz", "wt") as f:
    for i in range(1000):  # 1000 reads for quick demo
        f.write(f"@DEMO_READ_{i+1}_R2\n")
        f.write("TTTCCTCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGCTGC\n")
        f.write("+\n") 
        f.write("IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n")

print("Demo FASTQ files created!")
