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

baseDir=$(realpath ${1%/})     # directory to be processed, removing trailing slash
subjectID=${baseDir#*/sub-}

# To be able to run "find" you need to cd to a place where we have access,
# and it is possible that the call to "completeJSONs" is done from a place
# from which we don't have access
cd /tmp

for f in $(find ${baseDir} -name "qa.txt"); do
  # create a temporary file to work.
  tmpfile=$(mktemp /tmp/XXXXX.qa.txt)

  # First lines of the new file are fixed, CBI-wide:
  # (check to see if they are already present):
  myStr="# First, cd to the top level directory (including sub-XXXX)."
  if [[ $(head -1 $f) != $myStr ]]; then
    echo ${myStr} >> ${tmpfile}
    echo "cd ${baseDir}" >> ${tmpfile}
    echo "" >> ${tmpfile}
  fi

  if (grep "/opt/HCP-Pipelines/global/templates/" $f > /dev/null); then
    echo "# Then, define the following environmental variable:" >> ${tmpfile}
    echo "export TEMPLATEDIR=           # this is the folder with templates from the HCP Pipelines" >> ${tmpfile}
    echo "                              # (you can grab it from CBIUserData/cbishare/HCPPipelinesTemplates)" >> ${tmpfile}
    echo "" >> ${tmpfile}
  fi

  # To find the path that we need to replace, first, ignore lines
  # that start with "cd ", and then find a string: "*/sub-$subjectID*":
  someFile=$(grep -v "^cd " $f | grep -m 1 -Eo "[[:alnum:][:punct:]]+/sub-$subjectID[[:alnum:][:punct:]]+")
  # remove double slashes in the path, if present:
  someFile=$(echo $someFile | sed s#//*#/#g)
  # use python to get the common path
  matchingStr=$( python3 -c "from difflib import SequenceMatcher; string1='$someFile'; string2='$baseDir'; match = SequenceMatcher(None, string1, string2).find_longest_match(0, len(string1), 0, len(string2)); print(string1[match.a: match.a + match.size])" )

  # From the original file:
  #  1) remove the "cd /data/..." line
  #  2) replace the original template path with $TEMPLATEDIR
  #  3) replace the absolute path of the docker container
  #       with the absolute path in the host machine
  #  4) make this absolute path relative to the qa.txt file
  #  5) write the result to the temporary file
  sed -e "/^cd \/data\//d" \
      -e "s| /opt/HCP-Pipelines/global/templates/| \$TEMPLATEDIR/|g" \
      -e "s| ${someFile%%$matchingStr*}${matchingStr%sub-$subjectID*}[/]*sub-${subjectID}/| ./|g" \
  $f >> ${tmpfile}

  # copy them to the "deleteme" folder:
  #rf=${f#$baseDir/}; df=${rf%/qa.txt}; mkdir -p deleteme/${df};
  #mv ${tmpfile} deleteme/${df}/qa.txt
  mv ${tmpfile} ${f}
done

