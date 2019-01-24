#! /usr/bin/env bash

# ASSUMPTIONS:
# - the OPAM packages, specified by the user, are topologically sorted wrt. to the dependency relationship.
# - all the variables below are set.

set -e

if [ ! -z "$BENCH_DEBUG" ]
then
   set -x
fi

r='\033[0m'          # reset (all attributes off)
b='\033[1m'          # bold
u='\033[4m'          # underline

number_of_processors=$(cat /proc/cpuinfo | grep '^processor *' | wc -l)

program_name="$0"
program_path=$(readlink -f "${program_name%/*}")

# Check that the required arguments are provided

check_variable () {
  if [ ! -v "$1" ]
  then
      echo "Variable $1 should be set"
      exit 1
  fi
}

check_variable "WORKSPACE"
check_variable "BUILD_ID"
check_variable "new_ocaml_switch"
check_variable "new_coq_repository"
check_variable "new_coq_commit"
check_variable "new_coq_opam_archive_git_uri"
check_variable "new_coq_opam_archive_git_branch"
check_variable "old_ocaml_switch"
check_variable "old_coq_repository"
check_variable "old_coq_commit"
check_variable "num_of_iterations"
check_variable "coq_opam_packages"

if echo "$num_of_iterations" | grep '^[1-9][0-9]*$' 2> /dev/null > /dev/null; then
    :
else
    echo
    echo "ERROR: num_of_iterations \"$num_of_iterations\" is not a positive integer." > /dev/stderr
    print_man_page_hint
    exit 1
fi

working_dir="${WORKSPACE%@*}/$BUILD_ID"

if [ ! -z "$BENCH_DEBUG" ]
then
   echo "DEBUG: ocaml -version = `ocaml -version`"
   echo "DEBUG: working_dir = $working_dir"
   echo "DEBUG: new_ocaml_switch = $new_ocaml_switch"
   echo "DEBUG: new_coq_repository = $new_coq_repository"
   echo "DEBUG: new_coq_commit = $new_coq_commit"
   echo "DEBUG: new_coq_opam_archive_git_uri = $new_coq_opam_archive_git_uri"
   echo "DEBUG: new_coq_opam_archive_git_branch = $new_coq_opam_archive_git_branch"
   echo "DEBUG: old_ocaml_switch = $old_ocaml_switch"
   echo "DEBUG: old_coq_repository = $old_coq_repository"
   echo "DEBUG: old_coq_commit = $old_coq_commit"
   echo "DEBUG: num_of_iterations = $num_of_iterations"
   echo "DEBUG: coq_opam_packages = $coq_opam_packages"
fi

mkdir "$working_dir"

# --------------------------------------------------------------------------------

# Some sanity checks of command-line arguments provided by the user that can be done right now.

if which perf > /dev/null; then
    echo -n
else
    echo > /dev/stderr
    echo "ERROR: \"perf\" program is not available." > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

if [ ! -e "$working_dir" ]; then
    echo > /dev/stderr
    echo "ERROR: \"$working_dir\" does not exist." > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

if [ ! -d "$working_dir" ]; then
    echo > /dev/stderr
    echo "ERROR: \"$working_dir\" is not a directory." > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

if [ ! -w "$working_dir" ]; then
    echo > /dev/stderr
    echo "ERROR: \"$working_dir\" is not writable." > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

coq_opam_packages_on_separate_lines=$(echo "$coq_opam_packages" | sed 's/ /\n/g')
if [ $(echo "$coq_opam_packages_on_separate_lines" | wc -l) != $(echo "$coq_opam_packages_on_separate_lines" | sort | uniq | wc -l) ]; then
    echo "ERROR: The provided set of OPAM packages contains duplicates."
    exit 1
fi

# --------------------------------------------------------------------------------

# Clone the indicated git-repository.

coq_dir="$working_dir/coq"
git clone -q "$new_coq_repository" "$coq_dir"
cd "$coq_dir"
git remote rename origin new_coq_repository
git remote add old_coq_repository "$old_coq_repository"
git fetch -q "$old_coq_repository"
git checkout -q $new_coq_commit

official_coq_branch=master
coq_opam_version=dev

# --------------------------------------------------------------------------------

# Create a custom OPAM repository

custom_opam_repo="$working_dir/custom_opam_repo"

## Create a OPAM package that represents Coq branch designated by the user.
mkdir -p "$custom_opam_repo/packages/coq/coq.$coq_opam_version"

echo "opam-version: \"2.0\"" > "$custom_opam_repo/repo"

cat > "$custom_opam_repo/packages/coq/coq.$coq_opam_version/opam" <<+
opam-version: "2.0"
maintainer: "dummy@value.fr"
homepage: "http://dummy.value/"
bug-reports: "https://dummy.value/bugs/"
license: "LGPL 2"
build: [
  [ "./configure"
    "-prefix" prefix
    "-coqide" "no"
  ]
  [ make "-j" jobs ]
]
install: [make "install"]
depends: []
+

echo "url { src: \"file://$working_dir/coq\" } " >> "$custom_opam_repo/packages/coq/coq.$coq_opam_version/opam"

cat "$custom_opam_repo/packages/coq/coq.$coq_opam_version/opam"

# --------------------------------------------------------------------------------

new_opam_root="$working_dir/opam.NEW"
old_opam_root="$working_dir/opam.OLD"

# --------------------------------------------------------------------------------

old_coq_opam_archive_dir="$working_dir/old_coq_opam_archive"
git clone -q --depth 1 https://github.com/coq/opam-coq-archive.git "$old_coq_opam_archive_dir"
new_coq_opam_archive_dir="$working_dir/new_coq_opam_archive"
git clone -q --depth 1 -b "$new_coq_opam_archive_git_branch" "$new_coq_opam_archive_git_uri" "$new_coq_opam_archive_dir"

initial_opam_packages="num ocamlfind dune"

# Create an opam root and install Coq
# $1 = root_name {ex: NEW / OLD}
# $2 = compiler name
# $3 = git hash of Coq to be installed
# $4 = directory of coq opam archive
create_opam() {

    local OPAM_DIR="$working_dir/opam.$1"
    local OPAM_COMP="$2"
    local COQ_HASH="$3"
    local OPAM_COQ_DIR="$4"

    export OPAMROOT="$OPAM_DIR"

    opam init --disable-sandboxing -qn -j$number_of_processors --bare
    # Allow experimental compiler switches
    opam repo add -q --set-default ocaml-pr https://github.com/ocaml/ocaml-pr-repository.git
    # Rest of default switches
    opam repo add -q --set-default iris-dev "https://gitlab.mpi-sws.org/FP/opam-dev.git"
    opam repo add -q --set-default custom-opam-repo "$custom_opam_repo"

    opam switch create -qy -j$number_of_processors "$OPAM_COMP"
    eval $(opam env)

    # For some reason opam guesses an incorrect upper bound on the
    # number of jobs available on Travis, so we set it here manually:
    opam config set-global jobs $number_of_processors
    if [ ! -z "$BENCH_DEBUG" ]; then opam config list; fi

    opam repo add -q --this-switch coq-extra-dev "$OPAM_COQ_DIR/extra-dev"
    opam repo add -q --this-switch coq-released "$OPAM_COQ_DIR/released"

    opam install -qy -j$number_of_processors $initial_opam_packages
    if [ ! -z "$BENCH_DEBUG" ]; then opam repo list; fi

    cd "$coq_dir"
    if [ ! -z "$BENCH_DEBUG" ]; then echo "DEBUG: $1_coq_commit = $COQ_HASH"; fi

    git checkout -q $COQ_HASH
    COQ_HASH_LONG=$(git log --pretty=%H | head -n 1)

    if [ ! -z "$BENCH_DEBUG" ]; then echo "DEBUG: $1_coq_commit_long = $COQ_HASH_LONG"; fi

    if opam install -b -j$number_of_processors coq.$coq_opam_version; then
        echo "Coq installed successfully"
    else
        echo "ERROR: \"opam install coq.$coq_opam_version\" has failed (for the commit = $COQ_HASH_LONG)."
        exit 1
    fi

    opam pin --kind=version add coq $coq_opam_version
}

# Create an OPAM-root to which we will install the NEW version of Coq.
create_opam "NEW" "$new_ocaml_switch" "$new_coq_commit" "$new_coq_opam_archive_dir"
new_coq_commit_long="$COQ_HASH_LONG"

# Create an OPAM-root to which we will install the OLD version of Coq.
create_opam "OLD" "$old_ocaml_switch" "$old_coq_commit" "$old_coq_opam_archive_dir"
old_coq_commit_long="$COQ_HASH_LONG"
# --------------------------------------------------------------------------------
# Measure the compilation times of the specified OPAM packages in both switches

# Generate per line timing info in devs that use coq_makefile
export TIMING=1

# The following variable will be set in the following cycle:
installable_coq_opam_packages=

for coq_opam_package in $coq_opam_packages; do

    if [ ! -z "$BENCH_DEBUG" ]; then
        opam list
        echo "DEBUG: coq_opam_package = $coq_opam_package"
        opam show $coq_opam_package || continue 2
    fi

    for RUNNER in NEW OLD; do

        # perform measurements for the NEW/OLD commit (provided by the user)
        if [ $RUNNER = "NEW" ]; then
            export OPAMROOT="$new_opam_root"
            echo "Testing NEW commit"
        else
            export OPAMROOT="$old_opam_root"
            echo "Testing OLD commit"
        fi

        eval $(opam env)

        # If a given OPAM-package was already installed (as a
        # dependency of some OPAM-package that we have benchmarked
        # before), remove it.
        opam uninstall -q $coq_opam_package

        # OPAM 2.0 likes to ignore the -j when it feels like :S so we
        # workaround that here.
        opam config set-global jobs $number_of_processors

        opam install $coq_opam_package -v -b -j$number_of_processors --deps-only -y \
             3>$working_dir/$coq_opam_package.$RUNNER.opam_install.deps_only.stdout 1>&3 \
             4>$working_dir/$coq_opam_package.$RUNNER.opam_install.deps_only.stderr 2>&4 || continue 2

        opam config set-global jobs 1

        if [ ! -z "$BENCH_DEBUG" ]; then ls -l $working_dir; fi

        for iteration in $(seq $num_of_iterations); do
            _RES=0
            /usr/bin/time -o "$working_dir/$coq_opam_package.$RUNNER.$iteration.time" --format="%U %M %F" \
                 perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.$RUNNER.$iteration.perf" \
                    opam install -v -b -j1 $coq_opam_package \
                     3>$working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.stdout 1>&3 \
                     4>$working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.stderr 2>&4 || \
                _RES=$?
            if [ $_RES = 0 ];
            then
                echo $_RES > $working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.exit_status
                # "opam install" was successful.

                # Remove the benchmarked OPAM-package, unless this is the
                # very last iteration (we want to keep this OPAM-package
                # because other OPAM-packages we will benchmark later
                # might depend on it --- it would be a waste of time to
                # remove it now just to install it later)
                if [ $iteration != $num_of_iterations ]; then
                    opam uninstall -q $coq_opam_package
                fi
            else
                # "opam install" failed.
                echo $_RES > $working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.exit_status
                continue 3
            fi
        done
    done

    installable_coq_opam_packages="$installable_coq_opam_packages $coq_opam_package"

    # --------------------------------------------------------------

    # Print the intermediate results after we finish benchmarking each OPAM package
    if [ "$coq_opam_package" = "$(echo $coq_opam_packages | sed 's/ /\n/g' | tail -n 1)" ]; then

        # It does not make sense to print the intermediate results when
        # we finished bechmarking the very last OPAM package because the
        # next thing will do is that we will print the final results.
        # It would look lame to print the same table twice.
        :
    else

        echo "DEBUG: $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages"
        if [ ! -z "$BENCH_DEBUG" ]; then
            cat $working_dir/$coq_opam_package.$RUNNER.1.time || true
            cat $working_dir/$coq_opam_package.$RUNNER.1.perf || true
        fi
        $program_path/shared/render_results.ml "$working_dir" \
                                               $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages
    fi

    # Generate HTML report for LAST run

    new_base_path=$new_ocaml_switch/.opam-switch/build/$coq_opam_package.dev/
    old_base_path=$old_ocaml_switch/.opam-switch/build/$coq_opam_package.dev/
    for vo in `cd $new_opam_root/$new_base_path/; find -name '*.vo'`; do
        if [ -e $old_opam_root/$old_base_path/${vo%%o}.timing -a \
	        -e $new_opam_root/$new_base_path/${vo%%o}.timing ]; then
            mkdir -p $working_dir/html/$coq_opam_package/`dirname $vo`/
            $program_path/timelog2html $new_opam_root/$new_base_path/${vo%%o} \
	                               $old_opam_root/$old_base_path/${vo%%o}.timing \
	                               $new_opam_root/$new_base_path/${vo%%o}.timing > \
	                               $working_dir/html/$coq_opam_package/${vo%%o}.html
        fi
    done
done

# The following directories in $working_dir are no longer used:
#
# - coq, custom_opam_repo, opam.OLD, opam.NEW

# Measured data for each `$coq_opam_package`, `$iteration`, `status \in {NEW,OLD}`:
#
#     - $working_dir/$coq_opam_package.$status.$iteration.time
#       => output of /usr/bin/time --format="%U" ...
#
#     - $working_dir/$coq_opam_package.NEW.$iteration.perf
#       => output of perf stat -e instructions:u,cycles:u ...
#
# The next script processes all these files and prints results in a table.

echo "INFO: workspace = https://ci.inria.fr/coq/view/benchmarking/job/$JOB_NAME/ws/$BUILD_ID"

# Print the final results.
if [ -z "$installable_coq_opam_packages" ]; then
    # Tell the user that none of the OPAM-package(s) the user provided
    # /are installable.
    printf "\n\nINFO: failed to install: $coq_opam_packages"
    exit 1
else
    echo "DEBUG: $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages"
    $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages

    echo "INFO: per line timing: https://ci.inria.fr/coq/job/$JOB_NAME/ws/$BUILD_ID/html/"

    cd "$coq_dir"
    echo INFO: Old Coq version
    git log -n 1 "$old_coq_commit"
    echo INFO: New Coq version
    git log -n 1 "$new_coq_commit"

    not_installable_coq_opam_packages=`comm -23 <(echo $coq_opam_packages | sed 's/ /\n/g' | sort | uniq) <(echo $installable_coq_opam_packages | sed 's/ /\n/g' | sort | uniq) | sed 's/\t//g'`

    exit_code=0

    if [ ! -z "$not_installable_coq_opam_packages" ]; then
        # Tell the user that some of the provided OPAM-package(s)
        # is/are not installable.
        printf '\n\nINFO: failed to install %s\n' "$not_installable_coq_opam_packages"
        exit_code=1
    fi

    exit $exit_code
fi
