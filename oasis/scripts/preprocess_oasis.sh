#!/bin/bash
set -eu

SESSION=$1
if [ -z "$SESSION" ]; then
	echo "You need to give a session ID."
	echo "Example: ./oasis/scripts/preprocess_oasis.sh OAS30001_MR_d0129"
	exit 1
fi

RAW=oasis/data/raw/oasis3/$SESSION
DERIV=oasis/derivatives/$SESSION
MNI=$FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz
PYTHON=$HOME/misn-env/bin/python

mkdir -p $DERIV oasis/qc

# Take the first T1 alphabetically. Both runs have identical parameters,
# so there is no evidence-based reason to prefer either - consistency
# across subjects matters more than the choice.
T1=$(find $RAW -path "*anat*" -name "*T1w.nii.gz" | sort | head -1)

BOLD=""
BOLD_VOLUMES=0
for f in $(find $RAW -path "*func*" -name "*bold.nii.gz" | sort);do
	volumes=$(fslval $f dim4)
	if [ $volumes -gt $BOLD_VOLUMES ]; then
		BOLD_VOLUMES=$volumes
		BOLD=$f
	fi
done
echo "=== $SESSION ===="
echo "T1:	$T1"
echo "BOLD:	$BOLD ($BOLD_VOLUMES volumes)"

# 100 volumes is a thumb rule, not a hard threshold - reliabilty degrades
# gradually. Erring strict: losing one subject is a visible, countable loss,
# whereas accepting a marginal run adds noise that is invisible downstream.
if [ $BOLD_VOLUMES -lt 100 ]; then
	echo "ERROR: longest run has only $BOLD_VOLUMES volumes - too short for connnectivity."
	exit 1
fi
	
TR=$(fslval $BOLD pixdim4)
MIDDLE_VOLUME=$(( BOLD_VOLUMES / 2 ))
# 0.01 Hz high-pass cutoff = one cycle per 100 s. Divided by TR to get
# volumes, halved because -bptf takes half the period. Python because bash
# cannot divide decimals.
FILTER_SIGMA=$($PYTHON -c "print(round(100 / $TR / 2, 2))")
echo "TR:    $TR s"
echo "middle volume: $MIDDLE_VOLUME"
echo "filter sigma:  $FILTER_SIGMA"

echo "--- cropping neck ---"
# OASIS T1s include a lot of neck, which bet cannot handle - it left a large
# mass below the cerebellum that fast then segmented as brain. Cropping first
# fixes it. (ds002422 had little neck, so this step was not needed there.)
robustfov -i $T1 -r $DERIV/T1_cropped.nii.gz

echo "--- skull stripping ---"
bet $DERIV/T1_cropped.nii.gz $DERIV/T1_brain -f 0.5
echo "--- segmentation ---"
fast -B -o $DERIV/fast $DERIV/T1_brain.nii.gz
echo "--- T1 to MNI ---"
flirt -in $DERIV/T1_brain.nii.gz -ref $MNI -out $DERIV/T1_to_MNI.nii.gz -omat $DERIV/T1_to_MNI.mat -dof 12

echo "--- motion correction ---"
mcflirt -in $BOLD -out $DERIV/bold_mc -plots -report
# Slice timing skipped for all subject: syngo_MR_B13_4VB13A did not record
# SliceTiming, and correcting oly the scans that have it would make
# preprocessing differ in a way that tracks scan date, and so diagnosis

echo "--- coregistration ---"
fslroi $DERIV/bold_mc.nii.gz $DERIV/bold_ref.nii.gz $MIDDLE_VOLUME 1
epi_reg --epi=$DERIV/bold_ref.nii.gz --t1=$DERIV/T1_cropped.nii.gz --t1brain=$DERIV/T1_brain.nii.gz --out=$DERIV/bold2t1
convert_xfm -omat $DERIV/bold2mni.mat -concat $DERIV/T1_to_MNI.mat $DERIV/bold2t1.mat

echo "--- smoothing and filtering ---"
# 3 mm FWHM (sigma = FWHM/2.355). Fixed in mm rather than scaled to voxel
# size, so every subject gets the same absolute smoothing.
fslmaths $DERIV/bold_mc.nii.gz -s 1.27 $DERIV/bold_smooth.nii.gz
fslmaths $DERIV/bold_smooth.nii.gz -bptf $FILTER_SIGMA -1 $DERIV/bold_filtered.nii.gz

echo "--- confound regressors ---"
fslmaths $DERIV/fast_pve_2.nii.gz -thr 0.9 -bin $DERIV/wm_mask.nii.gz
fslmaths $DERIV/fast_pve_0.nii.gz -thr 0.9 -bin $DERIV/csf_mask.nii.gz
convert_xfm -omat $DERIV/t1_to_bold.mat -inverse $DERIV/bold2t1.mat
flirt -in $DERIV/wm_mask.nii.gz -ref $DERIV/bold_ref.nii.gz -applyxfm -init $DERIV/t1_to_bold.mat -out $DERIV/wm_mask_bold.nii.gz -interp nearestneighbour
flirt -in $DERIV/csf_mask.nii.gz -ref $DERIV/bold_ref.nii.gz -applyxfm -init $DERIV/t1_to_bold.mat -out $DERIV/csf_mask_bold.nii.gz -interp nearestneighbour
echo "WM mask:  $(fslstats $DERIV/wm_mask_bold.nii.gz -V | awk '{print $1}') voxels"
echo "CSF mask: $(fslstats $DERIV/csf_mask_bold.nii.gz -V | awk '{print $1}') voxels"
fslmeants -i $DERIV/bold_filtered.nii.gz -m $DERIV/wm_mask_bold.nii.gz -o $DERIV/wm_ts.txt
fslmeants -i $DERIV/bold_filtered.nii.gz -m $DERIV/csf_mask_bold.nii.gz -o $DERIV/csf_ts.txt

echo "--- nuisance regression ---"
paste $DERIV/bold_mc.par $DERIV/wm_ts.txt $DERIV/csf_ts.txt > $DERIV/confounds.txt
fsl_glm -i $DERIV/bold_filtered.nii.gz -d $DERIV/confounds.txt --out_res=$DERIV/bold_clean.nii.gz
echo "--- to MNI space ---"
flirt -in $DERIV/bold_clean.nii.gz -ref $MNI -applyxfm -init $DERIV/bold2mni.mat -out $DERIV/bold_clean_mni.nii.gz
echo "=== $SESSION: done ==="

