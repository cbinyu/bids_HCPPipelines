#!/usr/local/miniconda/bin/python

from bids import layout

def cbi_find_unique_runs(layout,run_list):

    # Function to find the unique different runs to be used as input to the anatomical pipelines
    # given a list of runs.  It checks if some of these runs have the same acquisition times and,
    # if there are some that do, picks the (first) non-normalized one.

    unique_runs_list = []
    acqTimes = [layout.get_metadata(thisRun)["AcquisitionTime"] for thisRun in run_list]
    uniqueAcqTimes = list(set(acqTimes))      # get the unique acquisition times

    for t in uniqueAcqTimes:
        # list all the runs with acq time 't':
        same_runs = [ r for r in run_list if layout.get_metadata(r)["AcquisitionTime"] == t ]

        # if there are more than one runs with that acq time,
        if len( same_runs ) > 1:
            # get the first non-normalized one:
            unnormalized_runs = [ r for r in same_runs if 'NORM' not in layout.get_metadata(r)["ImageType"] ]
            if len( unnormalized_runs ) > 0:
                run_to_be_added = unnormalized_runs[0]
            else:
                # if none, get the first normalized one:
                normalized_runs = [ r for r in same_runs if 'NORM' in layout.get_metadata(r)["ImageType"] ]
                run_to_be_added = normalized_runs[0]
        # if there is only one, use that one
        else:
            run_to_be_added = same_runs[0]

        # append to the list:
        unique_runs_list.append(run_to_be_added)

    return unique_runs_list
