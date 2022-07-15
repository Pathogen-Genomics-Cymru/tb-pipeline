// modules for the clockwork workflow

process alignToRef {
    /**
    * @QCcheckpoint fail if insufficient number and/or quality of read alignments to the reference genome
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_bam", mode: 'copy', overwrite: 'true', pattern: '*{.bam,.bam.bai,_alignmentStats.json}'
    publishDir "${params.output_dir}/$sample_name", mode: 'copy', overwrite: 'true', pattern: '*{.err,_report.json}'

    cpus 8

    memory '10 GB'

    input:
    tuple val(sample_name), path(fq1), path(fq2), path(json), val(doWeAlign)

    when:
    doWeAlign = ~ /NOW\_ALIGN\_TO\_REF\_${sample_name}/

    output:
    tuple val(sample_name), path("${sample_name}_report.json"), path("${sample_name}.bam"), path("${sample_name}.fa"), stdout, emit: alignToRef_bam
    path("${sample_name}.bam.bai", emit: alignToRef_bai)
    path("${sample_name}_alignmentStats.json", emit: alignToRef_json)
    path("${sample_name}.err", emit: alignToRef_err)

    script:
    bam = "${sample_name}.bam"
    bai = "${sample_name}.bam.bai"
    stats = "${sample_name}.stats"
    stats_json = "${sample_name}_alignmentStats.json"
    out_json = "${sample_name}_report.json"
    error_log = "${sample_name}.err"

    """
    ref_fa=\$(jq -r '.top_hit.file_paths.ref_fa' ${json})

    cp \${ref_fa} ${sample_name}.fa

    minimap2 -ax sr ${sample_name}.fa -t ${task.cpus} $fq1 $fq2 | samtools fixmate -m - - | samtools sort -T tmp - | samtools markdup --reference ${sample_name}.fa - minimap.bam

    java -jar /usr/local/bin/picard.jar AddOrReplaceReadGroups INPUT=minimap.bam OUTPUT=${bam} RGID=${sample_name} RGLB=lib RGPL=Illumina RGPU=unit RGSM=sample

    samtools index ${bam} ${bai}
    samtools stats ${bam} > ${stats}

    python3 ${baseDir}/bin/parse_samtools_stats.py ${bam} ${stats} > ${stats_json}
    python3 ${baseDir}/bin/create_final_json.py ${stats_json} ${json}

    continue=\$(jq -r '.summary_questions.continue_to_clockwork' ${out_json})
    if [ \$continue == 'yes' ]; then printf "NOW_VARCALL_${sample_name}" && printf "" >> ${error_log}; elif [ \$continue == 'no' ]; then echo "error: insufficient number and/or quality of read alignments to the reference genome" >> ${error_log}; fi
    """

    stub:
    bam = "${sample_name}.bam"
    bai = "${sample_name}.bam.bai"
    stats = "${sample_name}.stats"
    stats_json = "${sample_name}_alignmentStats.json"
    out_json = "${sample_name}_report.json"
    error_log = "${sample_name}.err"

    """
    touch ${sample_name}.fa
    touch ${bam}
    touch ${bai}
    touch ${stats}
    touch ${stats_json}
    touch ${out_json}
    touch ${error_log}
    printf ${params.alignToRef_doWeVarCall}
    """
}

process callVarsMpileup {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'

    cpus 8

    memory '5 GB'

    input:
    tuple val(sample_name), path(json), path(bam), path(ref), val(doWeVarCall)

    when:
    doWeVarCall =~ /NOW\_VARCALL\_${sample_name}/

    output:
    tuple val(sample_name), path("${sample_name}.samtools.vcf"), emit: mpileup_vcf

    script:
    samtools_vcf = "${sample_name}.samtools.vcf"

    """
    samtools mpileup -ugf ${ref} ${bam} | bcftools call --threads ${task.cpus} -vm -O v -o ${samtools_vcf}
    """

    stub:
    samtools_vcf = "${sample_name}.samtools.vcf"

    """
    touch ${samtools_vcf}
    """
}

process callVarsCortex {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'

    cpus 8

    memory '10 GB'

    input:
    tuple val(sample_name), path(json), path(bam), path(ref), val(doWeVarCall)

    when:
    doWeVarCall =~ /NOW\_VARCALL\_${sample_name}/

    output:
    tuple val(sample_name), path("${sample_name}.cortex.vcf"), emit: cortex_vcf

    script:
    cortex_vcf = "${sample_name}.cortex.vcf"

    """
    ref_dir=\$(jq -r '.top_hit.file_paths.clockwork_ref_dir' ${json})

    cp -r \${ref_dir}/* .

    clockwork cortex . ${bam} cortex ${sample_name}
    cp cortex/cortex.out/vcfs/cortex_wk_flow_I_RefCC_FINALcombined_BC_calls_at_all_k.raw.vcf ${cortex_vcf}
    """

    stub:
    cortex_vcf = "${sample_name}.cortex.vcf"

    """
    touch ${cortex_vcf}
    """
}

process minos {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'

    memory '10 GB'

    input:
    tuple val(sample_name), path(json), path(bam), path(ref), val(doWeVarCall), path(cortex_vcf), path(samtools_vcf)

    output:
    tuple val(sample_name), path("${sample_name}.minos.vcf"), emit: minos_vcf

    script:
    minos_vcf = "${sample_name}.minos.vcf"

    """
    awk '{print \$1}' ${ref} > ref.fa
    minos adjudicate --force --reads ${bam} minos ref.fa ${samtools_vcf} ${cortex_vcf}
    cp minos/final.vcf ${minos_vcf}
    rm -rf minos
    """

    stub:
    minos_vcf = "${sample_name}.minos.vcf"

    """
    touch ${minos_vcf}
    """
}

process gvcf {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }

    publishDir "${params.output_dir}/$sample_name/output_fasta", mode: 'copy', pattern: '*.fa'
    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf.gz'
    publishDir "${params.output_dir}/$sample_name", mode: 'copy', overwrite: 'true', pattern: '*.err'

    cpus 8

    memory '5 GB'

    input:
    tuple val(sample_name), path(json), path(bam), path(ref), val(doWeVarCall), path(minos_vcf)

    output:
    path("${sample_name}.gvcf.vcf.gz", emit: gvcf)
    path("${sample_name}.fa", emit: gvcf_fa)
    path("${sample_name}.err", emit: gvcf_log)

    script:
    gvcf = "${sample_name}.gvcf.vcf"
    gvcf_fa = "${sample_name}.fa"
    error_log = "${sample_name}.err"

    """
    awk '{print \$1}' ${ref} > ref.fa
    samtools mpileup -ugf ref.fa ${bam} | bcftools call --threads ${task.cpus} -m -O v -o samtools_all_pos.vcf
    clockwork gvcf_from_minos_and_samtools ref.fa ${minos_vcf} samtools_all_pos.vcf ${gvcf}
    clockwork gvcf_to_fasta ${gvcf} ${gvcf_fa}
    rm samtools_all_pos.vcf
    gzip ${gvcf}
    printf "workflow complete without error" >> ${error_log}
    """

    stub:
    gvcf = "${sample_name}.gvcf.vcf.gz"
    gvcf_fa = "${sample_name}.fa"
    error_log = "${sample_name}.err"

    """
    touch ${gvcf}
    touch ${gvcf_fa}
    touch ${error_log}
    """
}

