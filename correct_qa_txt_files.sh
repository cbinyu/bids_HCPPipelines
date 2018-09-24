#!/bin/bash

# Script to correct the qa.txt files in the HCP-processed data
#
# This is necessary because the pipelines are run in a docker
#   container and the output paths in the container are not
#   the same as in the host.
#
# In fact, if people copy and/or move the processed data around
#   the paths are no longer valid, so it is better to write all
#   the qa.txt files with paths relative to the top folder (the
#   output folder of the bids_hcppipelines + sub-XXXX)
# Also, for templates, users are asked to define the path to the
#   templates in a variable called "TEMPLATEDIR", which will be
#   machine dependent, and we use that variable in the qa.txt
#   files, instead of a hard-coded path.
#
# Input:
#   The output folder of the HCP-processed data (including sub-XXXX),
#     in the host machine file system (not the Docker container).
#

baseDir=${1%/}     # directory to be processed, removing trailing slash

for f in $(find ${baseDir} -name "qa.txt"); do
  # create a temporary file to work.
  tmpfile=$(mktemp /tmp/XXXXX.qa.txt)

  # First lines of the new file are fixed, CBI-wide:
  echo "# First, cd to the top level directory (including sub-XXXX)." >> ${tmpfile}
  echo "cd ${baseDir}" >> ${tmpfile}
  echo "" >> ${tmpfile}


  if (grep "/opt/HCP-Pipelines/global/templates/" $f > /dev/null); then
    echo "# Then, define the following environmental variable:" >> ${tmpfile}
    echo "export TEMPLATEDIR=           # this is the folder with templates from the HCP Pipelines" >> ${tmpfile}
    echo "                              # (you can grab it from CBIUserData/cbishare/HCPPipelinesTemplates)" >> ${tmpfile}
    echo "" >> ${tmpfile}
  fi

  # From the original file:
  #  1) remove the "cd /data/..." line
  #  2) replace the original template path with $TEMPLATEDIR
  #  3) replace the absolute path of the docker container
  #       with the absolute path in the host machine
  #  4) make this absolute path relative to the qa.txt file
  #  5) write the result to the temporary file
  sed -e "/^cd \/data\//d" \
      -e "s| /opt/HCP-Pipelines/global/templates/| \$TEMPLATEDIR/|g" \
      -e "s| /data//${baseDir#/CBI/UserData/}/| ./|g" \
  $f >> ${tmpfile}

  # copy them to the "deleteme" folder:
  #rf=${f#$baseDir/}; df=${rf%/qa.txt}; mkdir -p deleteme/${df};
  #mv ${tmpfile} deleteme/${df}/qa.txt
  mv ${tmpfile} ${f}
done

