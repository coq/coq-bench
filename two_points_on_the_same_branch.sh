#! /bin/bash -e

# :sy on
# :set expandtab
# :set smarttab
# :set tabstop=4
# :set shiftwidth=4

# ASSUMPTIONS:
# - "ocaml*" binaries visible via $PATH
# - num is installed
# - ocamlfind is installed and available in $PATH
# - camlp5 is installed and available in $PATH
# - the OPAM packages, specified by the user, are topologically sorted wrt. to the dependency relationship.

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
git clone "$new_coq_repository" "$coq_dir"
cd "$coq_dir"
git remote rename origin new_coq_repository
git remote add old_coq_repository "$old_coq_repository"
git fetch "$old_coq_repository"
git checkout $new_coq_commit

official_coq_branch=master
coq_opam_version=dev

# --------------------------------------------------------------------------------

# Create a custom OPAM repository

## Create a fake "camlp5.dev" package that, when installed, does nothing.
## We assume that "camlp5" program is already installed.
## If we let OPAM install some other camlp5 package, in general we would run into problems.

custom_opam_repo="$working_dir/custom_opam_repo"
mkdir -p "$custom_opam_repo/packages/camlp5/camlp5.dev"

## Create a OPAM package that represents Coq branch designated by the user.
mkdir -p "$custom_opam_repo/packages/coq/coq.$coq_opam_version"

cat > "$custom_opam_repo/packages/coq/coq.$coq_opam_version/opam" <<+
opam-version: "1.2"
maintainer: "dummy@value.fr"
homepage: "http://dummy.value/"
bug-reports: "https://dummy.value/bugs/"
license: "LGPL 2"
build: [
  ["./configure"
   "-prefix" prefix
    "-coqide" "no"
  ]
  [make "-j%{jobs}%"]
]
install: [make "install"]
depends: []
+

echo "local: \"$working_dir/coq\"" > $custom_opam_repo/packages/coq/coq.$coq_opam_version/url
touch $custom_opam_repo/packages/coq/coq.$coq_opam_version/descr

# --------------------------------------------------------------------------------

new_opam_root="$working_dir/opam.NEW"
old_opam_root="$working_dir/opam.OLD"

# --------------------------------------------------------------------------------

# Create a new OPAM-root to which we will install the NEW version of Coq.

export OPAMROOT="$new_opam_root"
initial_opam_packages="num ocamlfind camlp5"

echo n | opam init -v -j$number_of_processors --comp $new_ocaml_switch
echo $PATH
. "$OPAMROOT"/opam-init/init.sh
yes | opam install -v -j$number_of_processors $initial_opam_packages

new_coq_opam_archive_dir="$working_dir/new_coq_opam_archive"
git clone --depth 1 -b "$new_coq_opam_archive_git_branch" "$new_coq_opam_archive_git_uri" "$new_coq_opam_archive_dir"

opam repo add iris-dev "https://gitlab.mpi-sws.org/FP/opam-dev.git"
opam repo add custom-opam-repo "$custom_opam_repo"
opam repo add coq-extra-dev "$new_coq_opam_archive_dir/extra-dev"
opam repo add coq-released "$new_coq_opam_archive_dir/released"
opam repo list
cd "$coq_dir"
echo "DEBUG: new_coq_commit = $new_coq_commit"
git checkout $new_coq_commit
new_coq_commit_long=$(git log --pretty=%H | head -n 1)
echo "DEBUG: new_coq_commit_long = $new_coq_commit_long"

if opam install coq.$coq_opam_version -v -b -j$number_of_processors; then
    :
else
    echo "ERROR: \"opam install coq.$coq_opam_version\" has failed (for the NEWER commit = $head_long)."
    exit 1
fi

opam pin --kind=version add coq $coq_opam_version

# --------------------------------------------------------------------------------

# Create a new OPAM-root to which we will install the OLD version of Coq.

export OPAMROOT="$old_opam_root"

echo n | opam init -v -j$number_of_processors --comp $old_ocaml_switch
echo $PATH
. "$OPAMROOT"/opam-init/init.sh
yes | opam install -v -j$number_of_processors $initial_opam_packages

opam repo add iris-dev "https://gitlab.mpi-sws.org/FP/opam-dev.git"
opam repo add custom-opam-repo "$custom_opam_repo"

git clone --depth 1 https://github.com/coq/opam-coq-archive.git
opam repo add coq-extra-dev opam-coq-archive/extra-dev
opam repo add coq-released opam-coq-archive/released
opam repo list
cd "$coq_dir"
echo "DEBUG: old_coq_commit = $old_coq_commit"
git checkout $old_coq_commit
old_coq_commit_long=$(git log --pretty=%H | head -n 1)
echo "DEBUG: old_coq_commit_long = $old_coq_commit_long"

if opam install coq.$coq_opam_version -v -b -j$number_of_processors; then
    :
else
    echo "ERROR: \"opam install coq.$coq_opam_version\" has failed (for the NEWER commit = $head_long)."
    exit 1
fi

if [ ! $coq_opam_version = dev ]; then
  opam pin add coq $coq_opam_version
fi

# --------------------------------------------------------------------------------

# Measure the compilation times of the specified OPAM packages
# - for the NEW commit
# - for the OLD commit

# Generate per line timing info
export TIMING=1

# The following variable will be set in the following cycle:
installable_coq_opam_packages=

for coq_opam_package in $coq_opam_packages; do
    echo "DEBUG: coq_opam_package = $coq_opam_package"
    opam show $coq_opam_package || continue 2

  for RUNNER in NEW OLD; do
    # perform measurements for the NEW/OLD commit (provided by the user)
    if [ $RUNNER = "NEW" ]; then
      export OPAMROOT="$new_opam_root"
      echo "Testing NEW commit"
    else
      export OPAMROOT="$old_opam_root"
      echo "Testing OLD commit"
    fi
    . "$OPAMROOT"/opam-init/init.sh

    # If a given OPAM-package was already installed
    # (as a dependency of some OPAM-package that we have benchmarked before),
    # remove it.
    opam uninstall $coq_opam_package -v

    opam install $coq_opam_package -v -b -j$number_of_processors --deps-only -y \
         3>$working_dir/$coq_opam_package.$RUNNER.opam_install.deps_only.stdout 1>&3 \
         4>$working_dir/$coq_opam_package.$RUNNER.opam_install.deps_only.stderr 2>&4 || continue 2

    for iteration in $(seq $num_of_iterations); do
        if /usr/bin/time -o "$working_dir/$coq_opam_package.$RUNNER.$iteration.time" --format="%U %M %F" \
           perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.$RUNNER.$iteration.perf" \
           opam install $coq_opam_package -v -b -j1 \
           3>$working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.stdout 1>&3 \
           4>$working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.stderr 2>&4;
        then
            echo $? > $working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.exit_status
            # "opam install ...", we have started above, was successful.

            # Remove the benchmarked OPAM-package, unless this is the very last iteration
            # (we want to keep this OPAM-package because other OPAM-packages we will benchmark later might depend on it --- it would be a waste of time to remove it now just to install it later)
            if [ $iteration != $num_of_iterations ]; then
                opam uninstall $coq_opam_package -v
            fi
        else
            # "opam install ...", we have started above, failed.
            echo $? > $working_dir/$coq_opam_package.$RUNNER.opam_install.$iteration.exit_status
            continue 3
        fi
    done
  done

    installable_coq_opam_packages="$installable_coq_opam_packages $coq_opam_package"

    # --------------------------------------------------------------

    # Print the intermediate results after we finish benchmarking each OPAM package
    if [ "$coq_opam_package" = "$(echo $coq_opam_packages | sed 's/ /\n/g' | tail -n 1)" ]; then
        # It does not make sense to print the intermediate results when we finished bechmarking the very last OPAM package
        # because the next thing will do is that we will print the final results.
        # It would look lame to print the same table twice.
	:
    else
	echo "DEBUG: $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages"
        $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages
    fi

  # Generate HTML report for LAST run

  new_base_path=$new_ocaml_switch/build/$coq_opam_package.dev/
  old_base_path=$old_ocaml_switch/build/$coq_opam_package.dev/
  for vo in `cd $new_opam_root/$new_base_path/; find -name '*.vo'`; do
    if [ -e $old_opam_root/$old_base_path/${vo%%o}.timing -a \
	 -e $new_opam_root/$new_base_path/${vo%%o}.timing ]; then
      mkdir -p $working_dir/html/$coq_opam_package/`dirname $vo`/
      `dirname $0`/timelog2html $new_opam_root/$new_base_path/${vo%%o} \
	    $old_opam_root/$old_base_path/${vo%%o}.timing \
	    $new_opam_root/$new_base_path/${vo%%o}.timing > \
	    $working_dir/html/$coq_opam_package/${vo%%o}.html
    fi
  done

done


# The following directories are no longer relevant:
# - $working_dir/coq
# - $working_dir/camlp4
# - $working_dir/camlp5
# - $working_dir/custom_opam_repo
# - $working_dir/.opam
# - $working_dir/.opam.OLD
# - $working_dir/.opam.NEW
 

# These files hold the measured data:
#
# - for every $coq_opam_package
#
#   - for every $iteration
#
#     - $working_dir/$coq_opam_package.NEW.$iteration.time
#
#         This file contains the output of the
#
#           /usr/bin/time --format="%U" ...
#
#         command that was used to measure compilation time of a particular $coq_opam_package
#         in a particular $iteration at the NEW commit.
#
#     - $working_dir/$coq_opam_package.NEW.$iteration.perf
#
#         This file contains the output of the
#
#           perf stat -e instructions:u,cycles:u ...
#
#         command that was used to measure the total number of CPU instructions and CPU cycles
#         executed during the compilation of a particular $coq_opam_package in a particular $iteration
#         at the NEW commit.
#
#     - $working_dir/$coq_opam_package.OLD.$iteration.time
#
#         This file contains the output of the
#
#           /usr/bin/time --format="%U" ...
#
#         command that was used to measure compilation time of a particular $coq_opam_package
#         in a particular $iteration at the OLD commit.
#
#     - $working_dir/$coq_opam_package.OLD.$iteration.perf
#
#         This file contains the output of the
#
#           perf stat -e instructions:u,cycles:u ...
#
#         command that was used to measure the total number of CPU instructions and CPU cycles
#         executed during the compilation of a particular $coq_opam_package in a particular $iteration
#         at the OLD commit.
#
# The following script processes all these files and prints results in a comprehensible way.

# This command:
#
#   print_singular_or_plural  phrase_in_singular  phrase_in_plural   foo1 bar2 baz3 ... fooN
#
# will print
#
#   phrase_in_singular
#
# if N = 1 and:
#
#   phrase_in_plural
#
# otherwise.
function print_singular_or_plural {
    phrase_in_singular="$1"
    phrase_in_plural="$2"
    shift 2
    list_of_words="$*"

    if [ $(echo $list_of_words | wc -w) = 1 ]; then
        echo -n "$phrase_in_singular"
    else
        echo -n "$phrase_in_plural"
    fi
}

echo "INFO: workspace = https://ci.inria.fr/coq/view/benchmarking/job/$JOB_NAME/ws/$BUILD_ID"
# Print the final results.
if [ -z "$installable_coq_opam_packages" ]; then
    # Tell the user that none of the OPAM-package(s) the user provided is/are installable.
    printf "\n\nINFO: "; print_singular_or_plural "the given OPAM-package" "none of the given OPAM-packages" $coq_opam_packages; echo ":"
    for coq_opam_package in $coq_opam_packages; do
        echo "- $coq_opam_package"
    done
    print_singular_or_plural "cannot" "can" $coq_opam_packages; printf " be installed\n\n\n"
    exit 1
else
    echo "DEBUG: $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages"
    $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $new_coq_commit_long $old_coq_commit_long 0 user_time_pdiff $installable_coq_opam_packages

    echo INFO: per line timing: https://ci.inria.fr/coq/job/$JOB_NAME/ws/$BUILD_ID/html/

    cd $coq_dir
    echo INFO: Old Coq version
    git log -n 1 $old_coq_commit
    echo INFO: New Coq version
    git log -n 1 $new_coq_commit

    not_installable_coq_opam_packages=`comm -23 <(echo $coq_opam_packages | sed 's/ /\n/g' | sort | uniq) <(echo $installable_coq_opam_packages | sed 's/ /\n/g' | sort | uniq) | sed 's/\t//g'`

    exit_code=0
    if [ ! -z "$not_installable_coq_opam_packages" ]; then
        # Tell the user that some of the provided OPAM-package(s) is/are not installable.
        printf "\n\nINFO: the following OPAM-"; print_singular_or_plural "package" "packages" $not_installable_coq_opam_packages; echo ":"
        for coq_opam_package in $not_installable_coq_opam_packages; do
            echo "- $coq_opam_package"
        done
	printf "cannot be installed (exit 1)\n\n\n"
        exit_code=1
    fi

    exit $exit_code
fi
