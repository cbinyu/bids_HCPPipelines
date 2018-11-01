###########################################################
# This is the Dockerfile to build a machine that runs the #
# CBI modifications to the BIDS version of the HCP        #
# Pipelines (github.com/bids-apps/hcppipelines):          #
# * It filters the images that will be used for the       #
#   anatomical pipelines (so that it doesn't use scouts,  #
#   or both normalized and unnormalized versions of the   #
#   same run).                                            #
###########################################################


###   Start from the official bids/hcppipelines   ###
# We'll modify just the function we need to.
FROM bids/hcppipelines


###   make it only use the "highres" anatomical images:   ####
#     and only the unique ones:

COPY cbi_filter_runs.py /
RUN chmod a+r /cbi_filter_runs.py

# In the entry point function (/run.py), find the lines in which
# we find the T1ws and T2ws, and:
#   1) add the condition of "highres"
#   2) filter the runs, to only use unique ones (in case there are normalized and un-normalized):
RUN sed -i \
        -e "/type='T[12]w',/\
	   {N;s/\([ ]*\)extensions=/\1acq='highres',\n&/}" \
        -e "s/\([ ]*\)assert (len(t1ws)/\
\1from cbi_filter_runs import cbi_find_unique_runs\n\
\1t1ws = cbi_find_unique_runs(layout,t1ws)\n\
\1t2ws = cbi_find_unique_runs(layout,t2ws)\n&/" \
        -e "s/print(line)/print(line,end='')/" \
       /run.py

