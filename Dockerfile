###########################################################
# This is the Dockerfile to build a machine that runs the #
# CBI modifications to the BIDS version of the HCP        #
# Pipelines (github.com/bids-apps/hcppipelines):          #
# * It filters the images that will be used for the       #
#   anatomical pipelines (so that it doesn't use scouts,  #
#   or both normalized and unnormalized versions of the   #
#   same run).                                            #
###########################################################


###   Start by creating a "builder"   ###
#   It will be the official bids/hcppipelines, but we remove a bunch
#   of stuff we don't need (e.g., all GPU stuff, etc.)

ARG DEBIAN_VERSION=stretch
ARG BASE_PYTHON_VERSION=3.7
# (don't simply use PYTHON_VERSION bc. it's an env variable)
ARG BIDS_HCPPIPELINES_VERSION=v4.1.3-1

FROM bids/hcppipelines:${BIDS_HCPPIPELINES_VERSION} as builder

# Delete stuff we don't need:
RUN echo "\
    doc \
    data/first \
    data/atlases \
    data/possum \
    src \
    extras/src \
    bin/fslview \
    bin/*_gpu* \
    bin/*_cuda* \
    fslpython/pkgs \
    fslpython/envs/fslpython/lib/libQt5Web* \
    fslpython/envs/fslpython/lib/libvtk* \
    fslpython/envs/fslpython/lib/python3.7/site-packages/fsleyes* \
    fslpython/envs/fslpython/lib/python3.7/site-packages/pylint \
    fslpython/envs/fslpython/lib/python3.7/site-packages/jedi \
    fslpython/envs/fslpython/lib/python3.7/site-packages/PyQt5 \
    fslpython/envs/fslpython/lib/python3.7/site-packages/skimage/data \
    fslpython/envs/fslpython/lib/python3.7/site-packages/wx \
    fslpython/envs/fslpython/bin/pandoc* \
    fslpython/envs/fslpython/bin/qmake \
    fslpython/envs/fslpython/include/qt \
    fslpython/envs/fslpython/include/vtk* \
    fslpython/envs/fslpython/share/doc \
    fslpython/envs/fslpython/translations/qt* \
    fslpython/envs/fslpython/share/gir-1.0 \
" > /tmp/deleteme.txt && \
  for d in $(cat /tmp/deleteme.txt); do \
    rm -r ${FSLDIR}/$d ; \
  done && \
  find ${FSLDIR}/fslpython/envs/fslpython/lib/python3.7/site-packages/ -type d \( \
        -name "tests" \
	-o -name "test_files" \
	-o -name "test_data" \
	-o -name "sample_data" \
    \) -print0 | xargs -0 rm -r && \
  rm ${SUBJECTS_DIR}/sample*

# Delete not-needed FreeSurfer files:
RUN rm -r ${FREESURFER_HOME}/bin/*freeview* \
    ${FREESURFER_HOME}/bin/*_cuda \
    ${FREESURFER_HOME}/bin/mris_volmask_vtk.bin \
    ${FREESURFER_HOME}/lib/vtk \
    ${FREESURFER_HOME}/lib/KWWidgets

# Delete not-needed MatlabMCR libraries:
RUN rm -r ${MATLAB_COMPILER_RUNTIME}/bin/glnxa64/*_cuda*

# Delete and link duplicated libraries from miniconda:
# (for all of those files in miniconda/lib; if the same file exists in fslpython/lib;
#  and the files are identical (don't print out differences), delete the miniconda one
#  and link it to the fslpython one)
RUN for l in /usr/local/miniconda/lib/*.so* /usr/local/miniconda/lib/*.a ; do \
      [ -f ${FSLDIR}/fslpython/envs/fslpython/lib/$(basename $l) ] \
        && diff $l ${FSLDIR}/fslpython/envs/fslpython/lib/$(basename $l) > /dev/null \
	&& rm $l \
	&& ln -s ${FSLDIR}/fslpython/envs/fslpython/lib/$(basename $l) $l ; \
    done

# There are several libraries that are identical.
# We'll link them. Because Docker doesn't reduce the file size when you
# do a COPY --from=, I'll write a script with the linking process which
# we'll run at the Application stage. (In the first line, use single
# quotes so that the shell doesn't execute "!"):
RUN echo '#!/bin/bash' > /create_links.sh && \
  # libGL.so and libGLU.so: \
  for l in /opt/workbench/libs_linux64_software_opengl/libGL*.so; do \
    # if they are the same, delete and save command to link: \
    diff ${l} ${l}.1 \
      && rm ${l} \
      && echo "ln -s ./$(basename ${l}).1 ${l}" >> /create_links.sh ; \
    fullVersion=$(ls ${l}.1.?.*); \
    diff ${l}.1 ${fullVersion} \
      && rm ${l}.1 \
      && echo "ln -s ./$(basename ${fullVersion}) ${l}.1" >> /create_links.sh ; \
  done && \
  for l in ${FSLDIR}/lib/libvtk[IG]*.so; do \
    # if they are the same, delete and save command to link: \
    diff ${l} ${l}.5.0 \
      && rm ${l} \
      && echo "ln -s ./$(basename ${l}).5.0 ${l}" >> /create_links.sh ; \
    fullVersion=$(ls ${l}.5.0.?); \
    diff ${l}.5.0 ${fullVersion} \
      && rm ${l}.5.0 \
      && echo "ln -s ./$(basename ${fullVersion}) ${l}.5.0" >> /create_links.sh ; \
  done


# Delete some more unneeded stuff:
RUN rm -r /usr/local/miniconda/pkgs \
          /usr/lib/x86_64-linux-gnu/libLLVM*



#############

###  Now, get a new machine with only the essentials  ###
# Enter here those corresponding to the builder (bids/hcppipelines)

FROM python:${BASE_PYTHON_VERSION}-slim-${DEBIAN_VERSION} as Application

# This makes the BASE_PYTHON_VERSION available inside this stage
ARG BASE_PYTHON_VERSION
ENV PYTHON_LIB_PATH=/usr/local/lib/python${BASE_PYTHON_VERSION} \
    HCPPIPEDIR=/opt/HCP-Pipelines \
    CONNECTOME_WB="/opt/workbench" \
    FREESURFER_HOME=/opt/freesurfer \
    FSLDIR=/usr/local/fsl/ \
    FSLOUTPUTTYPE=NIFTI_GZ \
    MATLAB_COMPILER_RUNTIME="/opt/matlabmcr-2017b/v93"

ENV HCPPIPEDIR_Config=${HCPPIPEDIR}/global/config\
    HCPPIPEDIR_Global=${HCPPIPEDIR}/global/scripts \
    HCPPIPEDIR_Templates=${HCPPIPEDIR}/global/templates \
    CARET7DIR=${CONNECTOME_WB}/bin_linux64 \
    MNI_DIR=${FREESURFER_HOME}/mni \
    SUBJECTS_DIR=${FREESURFER_HOME}/subjects \
    MATLABCMD=${MATLAB_COMPILER_RUNTIME}/toolbox/matlab \
    MSMBINDIR=${HCPPIPEDIR}/MSMBinaries \
    MSMCONFIGDIR=${HCPPIPEDIR}/MSMConfig \
    PATH="${HCPPIPEDIR}/FreeSurfer/custom:${FREESURFER_HOME}/tktools\
:${FREESURFER_HOME}/mni/bin\
:${FREESURFER_HOME}/bin\
:${FSLDIR}/bin\
:/usr/local/miniconda/bin\
:$PATH" \
    LD_LIBRARY_PATH="${FSLDIR}/lib\
:${CONNECTOME_WB}/libs_linux64\
:${CONNECTOME_WB}/libs_linux64_software_opengl\
:${MATLAB_COMPILER_RUNTIME}/runtime/glnxa64\
:${MATLAB_COMPILER_RUNTIME}/bin/glnxa64\
:${MATLAB_COMPILER_RUNTIME}/sys/os/glnxa64\
:${LD_LIBRARY_PATH}"

ENV MINC_BIN_DIR=${MNI_DIR}/bin \
    MINC_LIB_DIR=${MNI_DIR}/lib \
    MNI_DATAPATH=${MNI_DIR}/data \
    PERL5LIB=${MNI_DIR}/lib/perl5/5.8.5 \
    MNI_PERL5LIB=${MNI_DIR}/lib/perl5/5.8.5


# Copy system binaries and libraries:
COPY --from=builder ./bin/tcsh ./bin/csh        /bin/
COPY --from=builder ./lib/x86_64-linux-gnu/     /lib/x86_64-linux-gnu/
COPY --from=builder ./usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=builder ./usr/bin/                  /usr/bin/
COPY --from=builder ./usr/local/bin/            /usr/local/bin/
COPY --from=builder ./usr/local/miniconda/      /usr/local/miniconda/
COPY --from=builder ./usr/share/perl/           /usr/share/perl/
# COPY --from=builder ./${PYTHON_LIB_PATH}/site-packages/      ${PYTHON_LIB_PATH}/site-packages/
COPY --from=builder ./etc/ld.so.conf.d/x86_64-linux-gnu_GL.conf \
        /etc/ld.so.conf.d/

# Copy HCP Pipelines:
COPY --from=builder ./${HCPPIPEDIR}/ ${HCPPIPEDIR}/

# Copy $FSLDIR stuff we need:
#COPY --from=builder ./${FSLDIR}/  ${FSLDIR}/
COPY --from=builder ./${FSLDIR}/bin/melodic \
    ./${FSLDIR}/bin/eddy_openmp \
    ./${FSLDIR}/bin/fnirt \
    ./${FSLDIR}/bin/flameo \
    ./${FSLDIR}/bin/topup \
    ./${FSLDIR}/bin/surf2surf \
    ./${FSLDIR}/bin/film_gls \
    ./${FSLDIR}/bin/applytopup \
    ./${FSLDIR}/bin/xfibres \
    ./${FSLDIR}/bin/vecreg \
    ./${FSLDIR}/bin/invwarp \
    ./${FSLDIR}/bin/new_invwarp \
    ./${FSLDIR}/bin/invwarp_exe \
    ./${FSLDIR}/bin/applywarp \
    ./${FSLDIR}/bin/convertwarp \
    ./${FSLDIR}/bin/fslmaths \
    ./${FSLDIR}/bin/midtrans \
    ./${FSLDIR}/bin/flirt \
    ./${FSLDIR}/bin/feat_model \
    ./${FSLDIR}/bin/mcflirt \
    ./${FSLDIR}/bin/fugue \
    ./${FSLDIR}/bin/fast \
    ./${FSLDIR}/bin/prelude \
    ./${FSLDIR}/bin/bet \
    ./${FSLDIR}/bin/bet2 \
    ./${FSLDIR}/bin/robustfov \
    ./${FSLDIR}/bin/makerot \
    ./${FSLDIR}/bin/fslmeants \
    ./${FSLDIR}/bin/fslval \
    ./${FSLDIR}/bin/slicetimer \
    ./${FSLDIR}/bin/fslsplit \
    ./${FSLDIR}/bin/imglob \
    ./${FSLDIR}/bin/imcp \
    ./${FSLDIR}/bin/imrm \
    ./${FSLDIR}/bin/immv \
    ./${FSLDIR}/bin/imtest \
    ./${FSLDIR}/bin/imln \
    ./${FSLDIR}/bin/convert_xfm \
    ./${FSLDIR}/bin/fslmerge \
    ./${FSLDIR}/bin/fslcomplex \
    ./${FSLDIR}/bin/fslroi \
    ./${FSLDIR}/bin/calc_grad_perc_dev \
    ./${FSLDIR}/bin/fsl_sub \
    ./${FSLDIR}/bin/fsl_anat \
    ./${FSLDIR}/bin/fslorient \
    ./${FSLDIR}/bin/fslreorient2std \
    ./${FSLDIR}/bin/fslstats \
    ./${FSLDIR}/bin/remove_ext \
    ./${FSLDIR}/bin/aff2rigid \
    ./${FSLDIR}/bin/epi_reg \
    ./${FSLDIR}/bin/zeropad \
    ./${FSLDIR}/bin/fsl_abspath \
    ./${FSLDIR}/bin/fsl_prepare_fieldmap \
    ./${FSLDIR}/bin/avscale \
    ./${FSLDIR}/bin/tmpnam \
    ./${FSLDIR}/bin/fslhd \
    ./${FSLDIR}/bin/fslswapdim \
    ./${FSLDIR}/bin/fslswapdim_exe \
    ./${FSLDIR}/bin/rmsdiff \
            ${FSLDIR}/bin/
COPY --from=builder ./${FSLDIR}/lib/libopenblas.so.0 \
    ./${FSLDIR}/lib/libgfortran.so.3 \
            ${FSLDIR}/lib/
COPY --from=builder ./${FSLDIR}/fslpython/envs/ ${FSLDIR}/fslpython/envs/
COPY --from=builder ./${FSLDIR}/data/standard/ ${FSLDIR}/data/standard/
COPY --from=builder ./${FSLDIR}/etc/flirtsch/ ${FSLDIR}/etc/flirtsch/
COPY --from=builder ./${FSLDIR}/etc/fslversion ${FSLDIR}/etc/


# Copy WorkBench Connectome:
COPY --from=builder ./${CARET7DIR}/wb_command      ${CARET7DIR}/
COPY --from=builder ./${CONNECTOME_WB}/exe_linux64/wb_command     ${CONNECTOME_WB}/exe_linux64/
COPY --from=builder ./${CONNECTOME_WB}/libs_linux64/         ${CONNECTOME_WB}/libs_linux64/
COPY --from=builder ./${CONNECTOME_WB}/libs_linux64_software_opengl/     ${CONNECTOME_WB}/libs_linux64_software_opengl/

# Copy FreeSurfer stuff:
#####
### TODO: Replace all of the following with:
#         - Deleting not-needed content in "average" folder at building stage
#         - Simply copying all ${FREESURFER_HOME}
#####
COPY --from=builder ./${FREESURFER_HOME}/bin/      ${FREESURFER_HOME}/bin/
COPY --from=builder ./${FREESURFER_HOME}/lib/      ${FREESURFER_HOME}/lib/
COPY --from=builder ./${FREESURFER_HOME}/mni/     ${FREESURFER_HOME}/mni/
COPY --from=builder ./${FREESURFER_HOME}/tktools/  ${FREESURFER_HOME}/tktools/
COPY --from=builder ./${FREESURFER_HOME}/fsafd/        ${FREESURFER_HOME}/fsafd/
COPY --from=builder ./${SUBJECTS_DIR}/    ${SUBJECTS_DIR}/
COPY --from=builder ./${FREESURFER_HOME}/license.txt \
    ./${FREESURFER_HOME}/build-stamp.txt \
    ./${FREESURFER_HOME}/sources.sh \
    ./${FREESURFER_HOME}/sources.csh \
    ./${FREESURFER_HOME}/SetUpFreeSurfer.sh \
    ./${FREESURFER_HOME}/SetUpFreeSurfer.csh \
    ./${FREESURFER_HOME}/FreeSurferEnv.csh \
    ./${FREESURFER_HOME}/FreeSurferColorLUT.txt \
    ./${FREESURFER_HOME}/ASegStatsLUT.txt \
    ./${FREESURFER_HOME}/WMParcStatsLUT.txt \
        ${FREESURFER_HOME}/
COPY --from=builder ./${FREESURFER_HOME}/average/RB_all_2016-05-10.vc700.gca \
    ./${FREESURFER_HOME}/average/RB_all_withskull_2016-05-10.vc700.gca \
    ./${FREESURFER_HOME}/average/lh.folding.atlas.acfb40.noaparc.i12.2016-08-02.tif \
    ./${FREESURFER_HOME}/average/rh.folding.atlas.acfb40.noaparc.i12.2016-08-02.tif \
    ./${FREESURFER_HOME}/average/lh.DKaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs \
    ./${FREESURFER_HOME}/average/rh.DKaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs \
    ./${FREESURFER_HOME}/average/711-2C_as_mni_average_305.4dfp.hdr \
    ./${FREESURFER_HOME}/average/711-2C_as_mni_average_305.4dfp.img \
    ./${FREESURFER_HOME}/average/711-2C_as_mni_average_305.4dfp.ifh \
    ./${FREESURFER_HOME}/average/711-2C_as_mni_average_305.4dfp.img.rec \
    ./${FREESURFER_HOME}/average/711-2C_as_mni_average_305.4dfp.mat \
    ./${FREESURFER_HOME}/average/711-2B_as_mni_average_305_mask.4dfp.hdr \
    ./${FREESURFER_HOME}/average/711-2B_as_mni_average_305_mask.4dfp.img \
    ./${FREESURFER_HOME}/average/711-2B_as_mni_average_305_mask.4dfp.ifh \
    ./${FREESURFER_HOME}/average/711-2B_as_mni_average_305_mask.4dfp.img.rec \
    ./${FREESURFER_HOME}/average/3T18yoSchwartzReactN32_as_orig.4dfp.hdr \
    ./${FREESURFER_HOME}/average/3T18yoSchwartzReactN32_as_orig.4dfp.img \
    ./${FREESURFER_HOME}/average/3T18yoSchwartzReactN32_as_orig.4dfp.ifh \
    ./${FREESURFER_HOME}/average/3T18yoSchwartzReactN32_as_orig.4dfp.img.rec \
    ./${FREESURFER_HOME}/average/3T18yoSchwartzReactN32_as_orig.4dfp.mat \
    ./${FREESURFER_HOME}/average/mni305.cor.mgz \
    ./${FREESURFER_HOME}/average/rigidly_aligned_brain_template.tif \
    ./${FREESURFER_HOME}/average/lh.CDaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs \
    ./${FREESURFER_HOME}/average/rh.CDaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs \
    ./${FREESURFER_HOME}/average/lh.DKTaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs \
    ./${FREESURFER_HOME}/average/rh.DKTaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs \
    ./${FREESURFER_HOME}/average/colortable_BA.txt \
        ${FREESURFER_HOME}/average/

# Create the links:
COPY --from=builder ./create_links.sh  /create_links.sh
RUN chmod u+x /create_links.sh && \
    /create_links.sh

# Make sure we cache all libraries:
RUN ldconfig

# Copy BIDS App wrappers:
COPY --from=builder ./run.py ./version          /

###   make it only use the "highres" anatomical images:   ####
#     and only the unique ones:

#COPY cbi_filter_runs.py /
#RUN chmod a+r /cbi_filter_runs.py

## In the entry point function (/run.py), find the lines in which
## we find the T1ws and T2ws, and:
##   1) add the condition of "highres"
##   2) filter the runs, to only use unique ones (in case there are normalized and un-normalized):
#RUN sed -i \
#        -e "/suffix='T[12]w',/\
#	   {N;s/\([ ]*\)extensions=/\1acq='highres',\n&/}" \
#        -e "s/\([ ]*\)assert (len(t1ws)/\
#\1from cbi_filter_runs import cbi_find_unique_runs\n\
#\1t1ws = cbi_find_unique_runs(layout,t1ws)\n&/" \
#	-e "s/\([ ]*\)if (len(t2ws)/\
#\1t2ws = cbi_find_unique_runs(layout,t2ws)\n&/" \
#        -e "s/print(line)/print(line,end='')/" \
#       /run.py

COPY --from=builder ./usr/lib/ /usr/lib/

ENTRYPOINT ["/run.py"]