#!/bin/bash
# preprocess_subject.sh — full structural + functional preprocessing for one subject
# Usage:  ./scripts/preprocess_subject.sh sub-01

set -e   # stop immediately if any command fails

SUB=$1
RAW=data/raw/ds002422/$SUB
DER=derivatives
MNI=$FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz
PY=$HOME/misn-env/bin/python

mkdir -p $DER/bet $DER/fast $DER/flirt $DER/mcflirt $DER/slicetimer $DER/epi_reg $DER/denoise qc

# ---------- STRUCTURAL ----------

echo "=== $SUB: skull stripping ==="
# -f 0.5 chosen after comparing 0.2 (left non-brain) and 0.8 (cut frontal lobe)
bet $RAW/anat/${SUB}_T1w.nii $DER/bet/${SUB}_T1w_brain -f 0.5

echo "=== $SUB: segmentation ==="
# -B corrects the bias field first, then classifies. pve_0=CSF, pve_1=GM, pve_2=WM
fast -B -o $DER/fast/$SUB $DER/bet/${SUB}_T1w_brain.nii.gz

echo "=== $SUB: T1 to MNI ==="
# 12 DOF: different brains, so scaling and shear are needed.
# FNIRT omitted - small gain for 10-30 min per subject.
flirt -in $DER/bet/${SUB}_T1w_brain.nii.gz -ref $MNI \
      -out $DER/flirt/${SUB}_T1_to_MNI.nii.gz \
      -omat $DER/flirt/${SUB}_T1_to_MNI.mat -dof 12

# ---------- FUNCTIONAL ----------

echo "=== $SUB: motion correction ==="
# 6 DOF: same head, so nothing should be resized.
# -plots writes the .par file, which becomes a nuisance regressor later.
mcflirt -in $RAW/func/${SUB}_task-rest_bold.nii.gz \
        -out $DER/mcflirt/${SUB}_bold_mc -plots -report

echo "=== $SUB: slice timing ==="
# Read the exact SliceTiming from the JSON rather than assuming an interleave
# pattern. slicetimer wants fractions of a TR, so divide by RepetitionTime.
$PY -c "
import json, numpy as np
with open('$RAW/func/${SUB}_task-rest_bold.json') as f:
    m = json.load(f)
np.savetxt('$DER/slicetimer/${SUB}_slicetiming.txt',
           np.array(m['SliceTiming']) / m['RepetitionTime'])
"

TR=$($PY -c "
import json
with open('$RAW/func/${SUB}_task-rest_bold.json') as f:
    print(json.load(f)['RepetitionTime'])
")

# Input is the MOTION-CORRECTED file: slice timing interpolates in time and
# assumes a voxel holds the same tissue across volumes.
slicetimer -i $DER/mcflirt/${SUB}_bold_mc.nii.gz \
           -o $DER/slicetimer/${SUB}_bold_st \
           --tcustom=$DER/slicetimer/${SUB}_slicetiming.txt -r $TR

echo "=== $SUB: coregistration ==="
# epi_reg needs 3D, so take the middle volume as a representative reference.
fslroi $DER/slicetimer/${SUB}_bold_st.nii.gz $DER/epi_reg/${SUB}_bold_ref.nii.gz 100 1

# BBR: aligns to the white/grey boundary, not intensities. Robust to the
# EPI distortion this dataset cannot correct (no fieldmap).
epi_reg --epi=$DER/epi_reg/${SUB}_bold_ref.nii.gz \
        --t1=$RAW/anat/${SUB}_T1w.nii \
        --t1brain=$DER/bet/${SUB}_T1w_brain.nii.gz \
        --out=$DER/epi_reg/${SUB}_bold2t1

# ---------- DENOISING ----------

echo "=== $SUB: smoothing and filtering ==="
# sigma 1.27 = 3mm FWHM (FWHM / 2.355). 6mm visibly destroyed internal
# structure at 3.59mm voxel size.
fslmaths $DER/slicetimer/${SUB}_bold_st.nii.gz -s 1.27 $DER/denoise/${SUB}_smooth.nii.gz

# High-pass only. sigma 14 = 0.01 Hz cutoff at this TR.
# No low-pass: breathing (~0.3 Hz) is far above the Nyquist limit for a
# 3.56 s TR, so it is aliased rather than present as itself.
fslmaths $DER/denoise/${SUB}_smooth.nii.gz -bptf 14 -1 $DER/denoise/${SUB}_filtered.nii.gz

echo "=== $SUB: building confound regressors ==="
# Strict threshold (0.9) so the masks contain only pure tissue - they are
# meant to be noise references, so any partial-volume grey matter defeats them.
fslmaths $DER/fast/${SUB}_pve_2.nii.gz -thr 0.9 -bin $DER/denoise/${SUB}_wm_mask.nii.gz
fslmaths $DER/fast/${SUB}_pve_0.nii.gz -thr 0.9 -bin $DER/denoise/${SUB}_csf_mask.nii.gz

# The masks are in T1 space; invert the BOLD->T1 matrix to bring them across.
# Cheaper to move the small mask than to resample 200 BOLD volumes.
convert_xfm -omat $DER/denoise/${SUB}_t1_to_bold.mat \
            -inverse $DER/epi_reg/${SUB}_bold2t1.mat

# nearestneighbour so the mask stays binary - default interpolation would
# produce fractional values.
flirt -in $DER/denoise/${SUB}_wm_mask.nii.gz \
      -ref $DER/epi_reg/${SUB}_bold_ref.nii.gz -applyxfm \
      -init $DER/denoise/${SUB}_t1_to_bold.mat \
      -out $DER/denoise/${SUB}_wm_mask_bold.nii.gz -interp nearestneighbour

flirt -in $DER/denoise/${SUB}_csf_mask.nii.gz \
      -ref $DER/epi_reg/${SUB}_bold_ref.nii.gz -applyxfm \
      -init $DER/denoise/${SUB}_t1_to_bold.mat \
      -out $DER/denoise/${SUB}_csf_mask_bold.nii.gz -interp nearestneighbour

# One number per volume: the average signal in tissue with no neural activity.
fslmeants -i $DER/denoise/${SUB}_filtered.nii.gz \
          -m $DER/denoise/${SUB}_wm_mask_bold.nii.gz \
          -o $DER/denoise/${SUB}_wm_ts.txt

fslmeants -i $DER/denoise/${SUB}_filtered.nii.gz \
          -m $DER/denoise/${SUB}_csf_mask_bold.nii.gz \
          -o $DER/denoise/${SUB}_csf_ts.txt

echo "=== $SUB: nuisance regression ==="
# 8 regressors: 6 motion parameters + WM + CSF.
# NO global signal regression - it is contested and mathematically forces
# negative correlations. Compared both on sub-01; using the safer default.
paste $DER/mcflirt/${SUB}_bold_mc.par \
      $DER/denoise/${SUB}_wm_ts.txt \
      $DER/denoise/${SUB}_csf_ts.txt > $DER/denoise/${SUB}_confounds.txt

fsl_glm -i $DER/denoise/${SUB}_filtered.nii.gz \
        -d $DER/denoise/${SUB}_confounds.txt \
        --out_res=$DER/denoise/${SUB}_clean.nii.gz

echo "=== $SUB: done ==="
