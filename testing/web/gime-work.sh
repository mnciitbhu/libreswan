#!/bin/bash

if test $# -lt 2; then
  cat >> /dev/stderr <<EOF

Usage:

    $0 <summarydir> <repodir> [ <first-hash> ]

Print an untested commit hash on stdout.  The commit is selected by
looking for the first:

   - HEAD

   - an untested merge point

   - an untested branch point

   - longest untested run of commits (split)

EOF
  exit 1
fi

webdir=$(dirname $0)

summarydir=$1 ; shift
repodir=$1 ; shift
if test $# -gt 0 ; then
    start_hash=$1 ; shift
else
    start_hash=$(${webdir}/earliest-commit.sh ${repodir} ${summarydir})
fi

print_selected() {
    echo selecting $1 at $2 1>&2
    ( cd ${repodir} && git show --no-patch $2 ) 1>&2
    echo $2
    exit 0
}

branch=$(${webdir}/gime-git-branch.sh ${repodir})
remote=$(${webdir}/gime-git-remote.sh ${repodir} ${branch})

# if there is no start hash then this is likely an empty directory.
if test -z "${start_hash}" ; then
    start_hash=$(cd ${repodir} && git show --no-patch --format=%h ${branch})
    print_selected HEAD ${start_hash}
fi

# Find the longest untested run of commits.

run=""
count=0

longest_bias=0
longest_length=0
longest_count=0
longest_hash=

point_hash=
point_count=0
point_name=

head_hash=
head_count=0

while read hashes ; do
    count=$(expr ${count} + 1)
    hash=$(set -- ${hashes} ; echo $1)

    # Skip uninteresting commits.
    interesting=$(${webdir}/git-interesting.sh ${repodir} ${hash})
    if test -z "${interesting}" ; then
	continue
    fi

    # already tested?
    if test -d $(echo ${summarydir}/*-g${hash}-* | awk '{print $1}'); then
	tested=true
    else
	tested=false
    fi

    # Save the first interesting HEAD commit; there must be one.

    if test -z "${head_hash}" ; then
	head_hash=${hash}
	head_count=${count}
	echo head ${head_hash} at ${head_count} 1>&2
	# bail early if untested; head always comes first.
	${tested} || break
    fi

    # Update the longest run if, after adjusting for a bias towards
    # earlier runs, it is longer; while repeatedly updating isn't the
    # most efficient it avoids the need to do updates in the various
    # code paths below.

    run_length=$(echo ${run} | wc -w)
    if test ${run_length} -gt $(expr ${longest_length} + ${longest_bias}) ; then
	longest_length=${run_length}
	longest_count=${count}
	longest_hash=$(echo ${run} | awk '{ print $(NF / 2 + 1)}')
	echo longest ${longest_hash} at ${longest_count} length ${longest_length} bias ${longest_bias} run ${run} 1>&2
    fi

    # If this is a really interesting commit (branch, merge, tag),
    # increment the bias so that earlier runs are prefered.  Do this
    # before discarding tested commits so that nothing is missed.
    # This somewhat double counts as both merge and branch points are
    # considered.

    case "${interesting}" in
	*:* )
	    longest_bias=$(expr ${longest_bias} + 1)
	    echo bias ${longest_bias} $(echo ${interesting} | cut -d: -f1) ${hash} at ${count} 1>&2
	    ;;
    esac

    # already tested? stop the current run and start again
    if ${tested}; then
	run=""
	continue
    fi

    # Save the first really interesting commit (branch, merge, tag;
    # and not just a simple change).
    #
    # Keep processing as still need to determine the longest run.  The
    # longest run may occure after this commit.  The only way to
    # determine that the longest run is before the first branch (say)
    # is to examining all commits.

    if test -z "${point_hash}" ; then
	case "${interesting}" in
	    *:* )
		point_hash=${hash}
		point_count=${count}
		point_name="$(echo ${interesting} | cut -d: -f1)-point"
		echo ${point_name} ${point_hash} at ${point_count} 1>&2
		run=""
		continue
		;;
	esac
    fi

    run="${run} ${hash}"

done < <(${webdir}/gime-git-revisions.sh \
		  ${repodir} \
		  --topo-order \
		  --children \
		  ${start_hash}..${remote})

# Now which came first?

echo HEAD ${head_hash} at ${head_count} 1>&2
echo POINT ${point_name} ${point_hash} at ${point_count} 1>&2
echo LONGEST ${longest_length} ${longest_count} ${longest_hash} 1>&2

if test ${head_count} -gt 0 \
	-a \( ${longest_count} -eq 0 -o ${head_count} -lt ${longest_count} \) \
	-a \( ${point_count} -eq 0 -o ${head_count} -lt ${point_count} \) \
	-a ! -d ${summarydir}/*-g${head_hash}-* ; then
    print_selected "head" ${head_hash}
elif test ${point_count} -gt 0 \
	  -a ${point_count} -lt ${longest_count} ; then
    print_selected ${point_name} ${point_hash}
elif test ${longest_count} -gt 0 ; then
    # Split the run in approx two.
    print_selected "longest-run" ${longest_hash}
fi

exit 1
