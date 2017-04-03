#! /bin/bash -e

# :sy on
# :set expandtab
# :set smarttab
# :set tabstop=4
# :set shiftwidth=4

# ASSUMPTIONS:
# - camlp5 is installed and available in $PATH
# - ocamlfind is installed and available in $PATH
# - "ocaml*" binaries visible via $PATH are the ones that were installed via "apt-get" rather than "opam".
#   (or, at least, their version matches)

# TODO
# - Take advantage of the --show-actions:
#   - make sure that the user can provide OPAM packages (for benchmarking) in arbitrary order
#     (without resorting to brute-force method where, for each of the benchmarked package, we start from scratch (fresh OPAM-root containting just the right version of Coq))
# - Figure out how to separate `download`, `build` and `install` actions.
# - make sure that the user can provide OPAM packages (for benchmarking) in arbitrary order
#   (without resorting to brute-force method where, for each of the benchmarked package, we start from scratch (fresh OPAM-root containting just the right version of Coq))
# - remove the (in fact) superfluous argument of this script.
#   - remove it also from the corresponding Jenkins jobs
# - run benchmarks that compare Coq 8.5 and 8.6 (for those OPAM packages that be installed to either version)
# - check how Ocaml people tackled the same problem
# - documentation ... add missing bits
#   - Emilio's suggestions (https://github.com/coq/coq/pull/434)
#     - Indeed I would add a section such as "Interpreting the numbers: for a 4x job,
#       the numbers mean the minimum time of 4 executions of opam install package ."
#   - Théos suggestions
#     - explain why it makes sense to take minimum
# - track compilation times of individual files
# - send a message to coq-dev about the benchmarking machinery
# - check Travis ... what it is building ... whether we are tracking the same set
#   - vst
# - compile released versions (if there is no released version, let's create some some unnoficial tar.gz and use that)
#   instead of a HEAD of some branch
# - observe the dependency between
#   - the total benchmarking time wrt. the number of iterations
#   - the achieved precision wrt. the number of iterations
#   and documented this.
# - figure out what to do with the "coq-hott" package
#   - currently we clone (and patch) Emilio's branch which is patched version of some old commit of upstream
#   - what we would like to compile is the HEAD of the upstream master branch
#   - how can we do that?
#   - track HoTT via our "opam-install*" jobs
# - Simplify the Jenkins jobs:
#   - https://ci.inria.fr/coq/view/coq-contribs/job/coq-contribs/
#   - https://ci.inria.fr/coq/view/opam/job/opam-install/
#   - https://ci.inria.fr/coq/view/benchmarking/job/benchmark-the-whole-branch/
#   - https://ci.inria.fr/coq/view/benchmarking/job/benchmark-part-of-the-branch/
#   Instead of requiring to specify two pieces of clumsy data:
#   - the git repository
#   - the name of the branch
#   require just one string that identifies github repo and the branch and can be copy&pasted from the github's pull request:
#   e.g.:
# - TODO list mentioned here:
#   https://ci.inria.fr/coq/view/benchmarking/job/benchmark-the-whole-branch/
# - Compare our set of the tracked OPAM packages with the one tracked via Travis.
#   - start tracking:
#     - tlc
#     - coq-unicoq
#     - coq-metacoq
# - reuse the real *.opam file for Coq (we just need custom "url" file)
# - add checks that user-provided NEW and OLD values have the expected chronological order
#   (i.e. NEW is a more recent commit than OLD)
# - improve initial checks (whether our assumptions hold)
# - camlp{4,5} ... probably we do not need the fake "camlp4" and "camlp5" packages
#   (there is a way to tell OPAM to use the camlp4/5 available on the system instead of compiling/installing it when some package depends on it)
# - describe the effect of the commands in the  EXAMPLES section
# - Figure out some way to measure just the interpretation of "build" section.
#   (not interpretation of the "url" file or "install" section in the *.opam file)
#   Figure out how to avoid measuring downloading of the actual OPAM package that is being done during "opam install".
#   (even when all its dependencies were already installed by "opam install --deps-only ...")
#   (suggested also by https://github.com/matejkosik/coq-bench/issues/1)
# - shared/*.ml ... deal with the TODO list which is located there
# - there are are multiple ways how to improve repsonsibility (shorten the benchmarking time)
#   - what we actually want to do is:
#     - given some set of OPAM packages that the user is interested in to benchmark
#     - we should use an existing machinery to infer all the OPAM packages that need to be install so that we can benchmark
#       all the OPAM packages required by the user
#     - install all these OPAM packages in the topological order
#     - where benchmarked packages will be installed with "-j1" and one by one
#       and non-benchmarked packages (in the topological order in betweeen the two benchmarked packages)
#       will be installed with "-j4"
#       - Hmmm, now I realize that we could use more processors;
#         it could indeed contribute to the speedup (of installation of the non-benchmarked packages)
# - instead of abusing "opam" for the purposes for which it wasn't designed
#   ("opam" does not make it easy for me to test custom Coq branches)
#   make a cleaner implementation of this script by using some tool that directly supports what I need
#   (we can piggy-back on the ecosystem of "opam" and "url" file that is in place but shun the "opam" program which serves a different purpose)
# - merge these scripts under the Coq-organization umbrella (somewhere)
# - Maxime's suggestion:
#   - Maybe we could try a hybrid approach, like using opam to install dependencies, but do the build to be benchmarked manually.
#     This way, we would not need to create a fake package, we would have more control on what we measure,
#     but could still rely on OPAM to solve dependencies."
# - Emilio's suggestions
#   - we should benchmark every commit
#   - we should gather results per-file (rather than per OPAM package)
#   - we should gather and compare results per section or per sentence (sercomp will provide necessary mechanisms)
#   - We should benchmark every commit automatically and save the reports in a format that's easy to browse.
# - benchmarking results (for the official branches; for the released packages)
#   should be stored in some way to enable further proessing
#   - e.g. to display the trend for a given package
# - once we create v8.7 branch of Coq
#   - update:
#     - the "print_man_page" command
#     - the piece of code where we set the "official_coq_branch" variable
#     - the piece of code where we set the "coq_opam_version" variable

r='\033[0m'          # reset (all attributes off)
b='\033[1m'          # bold
u='\033[4m'          # underline

number_of_processors=$(cat /proc/cpuinfo | grep '^processor *' | wc -l)

program_name="$0"
program_path=$(readlink -f "${program_name%/*}")
program_name="${program_name##*/}"
synopsys1="\t$b$program_name$r  [$b-h$r | $b--help$r]"
synopsys2="\t$b$program_name$r  ${u}working_dir$r  ${u}coq_repository$r  ${u}coq_branch$r  ${u}num_of_iterations$r  ${u}coq_opam_package_1$r [${u}coq_opam_package_2$r  ... [${u}coq_opam_package_N$r}] ... ]]"
synopsys3="\t$b$program_name$r  ${u}working_dir$r  ${u}coq_repository$r  ${u}coq_branch$r${b}:$r${u}head$r${b}:$r${u}base$r  ${u}num_of_iterations$r  ${u}coq_opam_package_1$r [${u}coq_opam_package_2$r  ... [${u}coq_opam_package_N$r}] ... ]]"

# Print the "manual page" for this script.
print_man_page () {
    echo
    echo -e ${b}NAME$r
    echo
    echo -e "\t$program_name - run Coq benchmarks"
    echo
    echo -e ${b}SYNOPSIS$r
    echo
    echo -e "$synopsys1"
    echo
    echo -e "$synopsys2"
    echo
    echo -e "$synopsys3"
    echo
    echo -e ${b}DESCRIPTION
    echo
    echo -e "$synopsys1"
    echo
    echo -e "\t\tPrint this help."
    echo
    echo -e "$synopsys2"
    echo
    echo -e "\t\tClone a given ${u}coq_branch$r from a given ${u}coq_repository$r."
    echo -e "\t\tDetermine the name of the official Coq branch (i.e. either ${b}trunk$r or ${b}v8.6$r or ${b}v8.5$r)"
    echo -e "\t\t  from which a given ${u}coq_branch$r was branched."
    echo -e "\t\tMeasure compilation times of given Coq OPAM packages on this official Coq branch."
    echo -e "\t\tMeasure compilation times of given Coq OPAM packages at the HEAD of a given ${u}coq_branch$r."
    echo -e "\t\tCompare the compilation times and print the summary."
    echo
    echo -e "\t\t${u}num_of_iterations$r determines how many times each of the Coq OPAM packages should be compiled."
    echo
    echo -e "\t\tAll the temporary files are created inside a given ${u}working_dir$r."
    echo
    echo -e "$synopsys3"
    echo
    echo -e "\t\tLike above but instead of comparing the HEAD of the branch with the corresponding merge-base point,"
    echo -e "\t\tcompare the commits explicitely provided by the user (${u}head$r and ${u}base$r)."
    echo
    echo -e ${b}EXAMPLES$r
    echo
    echo -e "\t$b$program_name /tmp https://github.com/SkySkimmer/coq.git always-fast-typeops 3 coq-mathcomp-algebra coq-mathcomp-character$r"
    echo
    echo -e "\t$b$program_name /tmp https://github.com/coq/coq.git v8.6:HEAD:d0afde58 3 coq-persistent-union-find$r"
    echo
}

print_man_page_hint () {
    echo
    echo "See:"
    echo
    echo "    $program_name --help"
    echo
}

# --------------------------------------------------------------------------------

# Process command line arguments

case $# in
    0)
        print_man_page
        exit
        ;;
    1)
        case $1 in
            "-h" | "--help")
                print_man_page
                exit
                ;;
            *)
                echo > /dev/stderr
                echo ERROR: unrecognized command-line argument \"$1\". > /dev/stderr
                print_man_page_hint
                exit 1
                ;;
        esac
        ;;
    2 | 3 | 4)
        echo > /dev/stderr
        echo ERROR: wrong number of arguments. > /dev/stderr
        print_man_page_hint
        exit 1
        ;;
    *)
        working_dir="$1"
        coq_repository="$2"
        coq_branch="$3"
        if echo "$4" | grep '^[1-9][0-9]*$' 2> /dev/null > /dev/null; then
            num_of_iterations=$4
        else
            echo
            echo ERROR: the fourth command-line argument \"$4\" is not a positive integer.
            print_man_page_hint
            exit 1
        fi
        shift 4
        coq_opam_packages=$@
        ;;
esac

echo DEBUG: ocaml -version = `ocaml -version`
echo DEBUG: working_dir = $working_dir
echo DEBUG: coq_repository = $coq_repository
echo DEBUG: coq_branch = $coq_branch
echo DEBUG: num_of_iterations = $num_of_iterations
echo DEBUG: coq_opam_packages = $coq_opam_packages

# --------------------------------------------------------------------------------

# Some sanity checks of command-line arguments provided by the user that can be done right now.

if which perf > /dev/null; then
    echo -n
else
    echo > /dev/stderr
    echo ERROR: \"perf\" program is not available. > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

if [ ! -e "$working_dir" ]; then
    echo > /dev/stderr
    echo ERROR: \"$working_dir\" does not exist. > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

if [ ! -d "$working_dir" ]; then
    echo > /dev/stderr
    echo ERROR: \"$working_dir\" is not a directory. > /dev/stderr
    echo > /dev/stderr
    exit 1
fi

if [ ! -w "$working_dir" ]; then
    echo > /dev/stderr
    echo ERROR: \"working_dir\" is not writable. > /dev/stderr
    echo > /dev/stderr
fi

# --------------------------------------------------------------------------------

# Clone the designated git-branch from the designated git-repository.

coq_dir="$working_dir/coq"
git clone -b "${coq_branch%%:*}" "$coq_repository" "$coq_dir"
cd "$coq_dir"

# Detect the official Coq branch
#
# The computation below is based on the following assumptions:
# - 15edfc8f92477457bcefe525ce1cea160e4c6560 is the oldest commit in "trunk" which is not present neither in "v8.6", nor in "v8.5" branches.
# - bb43730ac876b8de79967090afa50f00858af6d5 is the oldest commit in "trunk" and "v8.6" which is not present in "v8.5".
# - 784d82dc1a709c4c262665a4cd4eb0b1bd1487a0 is the oldest commit that is present in "trunk" and "v8.6" and "v8.5" (but not in "v8.4").
if git log | grep 15edfc8f92477457bcefe525ce1cea160e4c6560 > /dev/null; then
    official_coq_branch=trunk
elif git log | grep bb43730ac876b8de79967090afa50f00858af6d5 > /dev/null; then
    official_coq_branch=v8.6
elif git log | grep 784d82dc1a709c4c262665a4cd4eb0b1bd1487a0 > /dev/null; then
    official_coq_branch=v8.5
else
    echo "ERROR: unrecognized Coq branch (neither \"v8.5\", nor \"v8.6\", nor \"trunk\")"
    exit 1
fi

if echo "$coq_branch" | grep '^[^:]*:[^:]*:[^:]*$' > /dev/null; then
    head=$(echo $coq_branch | awk -F: '{print $2}')
    base=$(echo $coq_branch | awk -F: '{print $3}')
    coq_branch=$(echo $coq_branch | awk -F: '{print $1}')
else
    head=HEAD
    git remote add upstream https://github.com/coq/coq.git
    git fetch upstream $official_coq_branch
    base=$(git merge-base upstream/$official_coq_branch "$coq_branch")
fi

echo "DEBUG: coq_branch = $coq_branch"
echo "DEBUG: NEW (commit) = $head"
echo "DEBUG: OLD (commit) = $base"

## Compute the OPAM version code corresponding to the compute name of the Coq branch
case $official_coq_branch in
    trunk)
        coq_opam_version=dev
        ;;
    v8.6)
        coq_opam_version=8.6.dev
        ;;
    v8.5)
        coq_opam_version=8.5.dev
        ;;
    *)
        echo ERROR: unexpected value \"$official_coq_branch\" of \"official_coq_branch\" variable.
        exit 1
esac

echo DEBUG: official_coq_branch = $official_coq_branch
echo DEBUG: coq_opam_version = $coq_opam_version

# --------------------------------------------------------------------------------

# Create a custom OPAM repository

## Create a fake "camlp5.dev" package that, when installed, does nothing.
## We assume that "camlp5" program is already installed.
## If we let OPAM install some other camlp5 package, in general we would run into problems.

custom_opam_repo="$working_dir/custom_opam_repo"
mkdir -p "$custom_opam_repo/packages/camlp5/camlp5.dev"

cat > "$custom_opam_repo/packages/camlp5/camlp5.dev/opam" <<+
opam-version: "1.2"
maintainer: "dummy@value.fr"
authors: ["Dummy Value"]
homepage: "https://dummy.value"
license: "dummy value"
build: []
available: []
bug-reports: "https://dummy.value"
dev-repo: "https://dummy.value.git"
doc: "https://dummy.value"
install: []
remove: []
+

camlp5_dir="$working_dir/camlp5"
mkdir -p "$camlp5_dir"
cat > "$custom_opam_repo/packages/camlp5/camlp5.dev/url" <<+
local: "$working_dir/camlp5"
+

touch "$custom_opam_repo/packages/camlp5/camlp5.dev/descr"

## Create a fake "camlp4.dev" package that, when installed, does nothing.
## We assume that "camlp4" program is already installed.
## If we let OPAM install some other camlp4 package, in general we would run into problems.

mkdir -p "$custom_opam_repo/packages/camlp4/camlp4.dev"

cat > "$custom_opam_repo/packages/camlp4/camlp4.dev/opam" <<+
opam-version: "1.2"
maintainer: "dummy@value.fr"
authors: ["Dummy Value"]
homepage: "https://dummy.value"
license: "dummy value"
build: []
available: []
bug-reports: "https://dummy.value"
dev-repo: "https://dummy.value.git"
doc: "https://dummy.value"
install: []
remove: []
+

camlp4_dir="$working_dir/camlp4"
mkdir -p "$camlp4_dir"
cat > "$custom_opam_repo/packages/camlp4/camlp4.dev/url" <<+
local: "$working_dir/camlp4"
+

touch "$custom_opam_repo/packages/camlp4/camlp4.dev/descr"

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
    "-usecamlp5"
    "-coqide" "no"
    "-nodoc"
  ]
  [make "-j%{jobs}%"]
]
install: [make "install"]
depends: []
+

echo "local: \"$working_dir/coq\"" > $custom_opam_repo/packages/coq/coq.$coq_opam_version/url
touch $custom_opam_repo/packages/coq/coq.$coq_opam_version/descr

# --------------------------------------------------------------------------------

# Set the OPAM root

export OPAMROOT="$working_dir/.opam"

# --------------------------------------------------------------------------------

# Create a new OPAM-root to which we will install the HEAD of the designated branch of Coq

echo n | opam init -v
echo $PATH
. "$OPAMROOT"/opam-init/init.sh

opam repo add custom-opam-repo "$custom_opam_repo"
opam repo add coq-extra-dev https://coq.inria.fr/opam/extra-dev
opam repo add coq-released https://coq.inria.fr/opam/released
opam repo add coq-bench $HOME/git/coq-bench/opam
opam repo list
cd "$coq_dir"
git checkout $head
head_long=$(git log --pretty=%H | head -n 1)
echo "DEBUG: git commit for HEAD = $head_long"

if opam install coq.$coq_opam_version -v -b -j$number_of_processors; then
    # all is well
    :
else
    echo "ERROR: \"opam install coq.$coq_opam_version\" has failed (for the NEWER commit = $head_long)."
    exit 1
fi

if [ ! $coq_opam_version = dev ]; then
  opam pin add coq $coq_opam_version
fi

mv "$OPAMROOT" "$OPAMROOT.NEW"

# --------------------------------------------------------------------------------

# Create a new OPAM-root to which we will install the BASE of the designated branch of Coq

echo n | opam init -v -j$number_of_processors

opam repo add custom-opam-repo "$custom_opam_repo"
opam repo add coq-extra-dev https://coq.inria.fr/opam/extra-dev
opam repo add coq-released https://coq.inria.fr/opam/released
opam repo add coq-bench $HOME/git/coq-bench/opam
opam repo list
cd "$coq_dir"
git checkout $base
base_long=$(git log --pretty=%H | head -n 1)
echo "DEBUG: git commit for BASE = $base_long"

if opam install coq.$coq_opam_version -v -b -j$number_of_processors; then
    # all is well
    :
else
    echo "ERROR: \"opam install coq.$coq_opam_version\" has failed (for the NEWER commit = $head_long)."
    exit 1
fi

if [ ! $coq_opam_version = dev ]; then
  opam pin add coq $coq_opam_version
fi

mv "$OPAMROOT" "$OPAMROOT.OLD"

# --------------------------------------------------------------------------------

# Measure the compilation times of the specified OPAM packages
# - at the HEAD of the indicated branch
# - at the BASE of the indicated branch

export OPAMROOT="$working_dir/.opam"

# The following variable will be set in the following cycle:
installable_coq_opam_packages=

for coq_opam_package in $coq_opam_packages; do
    echo "DEBUG: coq_opam_package = $coq_opam_package"

    # perform measurements for the NEW commit (provided by the user)
    mv "$OPAMROOT.NEW" "$OPAMROOT"

    # If a given OPAM-package was already installed
    # (as a dependency of some OPAM-package that we have benchmarked before),
    # remove it.
    opam uninstall $coq_opam_package -v

    $program_path/shared/opam_install.sh $coq_opam_package -v -b -j$number_of_processors --deps-only -y
    for iteration in $(seq $num_of_iterations); do
        if /usr/bin/time -o "$working_dir/$coq_opam_package.NEW.$iteration.time" --format="%U" \
           perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.NEW.$iteration.perf" \
           opam install $coq_opam_package -v -b -j1;
        then
            # "opam install ...", we have started above, was successful.

            # Remove the benchmarked OPAM-package, unless this is the very last iteration
            # (we want to keep this OPAM-package because other OPAM-packages we will benchmark later might depend on it --- it would be a waste of time to remove it now just to install it later)
            if [ $iteration != $num_of_iterations ]; then
                opam uninstall $coq_opam_package -v
            fi
        else
            # "opam install ...", we have started above, failed.
            mv "$OPAMROOT" "$OPAMROOT.NEW"
            continue 2
        fi
    done
    mv "$OPAMROOT" "$OPAMROOT.NEW"

    # perform measurements for the OLD commit (provided by the user)
    mv "$OPAMROOT.OLD" "$OPAMROOT"

    # If a given OPAM-package was already installed
    # (as a dependency of some OPAM-package that we have benchmarked before),
    # remove it.
    opam uninstall $coq_opam_package -v

    $program_path/shared/opam_install.sh $coq_opam_package -v -j$number_of_processors --deps-only -y
    for iteration in $(seq $num_of_iterations); do
        if /usr/bin/time -o "$working_dir/$coq_opam_package.OLD.$iteration.time" --format="%U" \
           perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.OLD.$iteration.perf" \
           opam install $coq_opam_package -v -j1;
        then
            # "opam install ...", we have started above, was successful.

            # Remove the benchmarked OPAM-package, unless this is the very last iteration
            # (we want to keep this OPAM-package because other OPAM-packages we will benchmark later might depend on it --- it would be a waste of time to remove it now just to install it later)
            if [ $iteration != $num_of_iterations ]; then
                opam uninstall $coq_opam_package -v
            fi
        else
            # "opam install ...", we have started above, failed.
            mv "$OPAMROOT" "$OPAMROOT.OLD"
            continue 2
        fi
    done
    mv "$OPAMROOT" "$OPAMROOT.OLD"

    installable_coq_opam_packages="$installable_coq_opam_packages $coq_opam_package"

    # Print the intermediate results after we finish benchmarking an OPAM package.
    echo "DEBUG: $program_path/render_results.ml "$working_dir" $num_of_iterations $head_long $base_long 0 user_time_pdiff $installable_coq_opam_packages"
    $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $head_long $base_long 0 user_time_pdiff $installable_coq_opam_packages
done

echo "DEBUG: coq_opam_packages = $coq_opam_packages"
echo "DEBUG: installable_coq_opam_packages = $installable_coq_opam_packages"

# The following directories are no longer relevant:
# - $working_dir/coq
# - $working_dir/camlp4
# - $working_dir/camlp5
# - $working_dir/custom_opam_repo
# - $working_dir/.opam
# - $working_dir/.opam.BASE
# - $working_dir/.opam.HEAD
 

# These files hold the measured data:
#
# - for every $coq_opam_package
#
#   - for every $iteration
#
#     - $working_dir/$coq_opam_package.HEAD.$iteration.time
#
#         This file contains the output of the
#
#           /usr/bin/time --format="%U" ...
#
#         command that was used to measure compilation time of a particular $coq_opam_package
#         in a particular $iteration at the HEAD of a given $coq_branch.
#
#     - $working_dir/$coq_opam_package.HEAD.$iteration.perf
#
#         This file contains the output of the
#
#           perf stat -e instructions:u,cycles:u ...
#
#         command that was used to measure the total number of CPU instructions and CPU cycles
#         executed during the compilation of a particular $coq_opam_package in a particular $iteration
#         at the HEAD of a given $coq_branch.
#
#     - $working_dir/$coq_opam_package.BASE$iteration.time
#
#         This file contains the output of the
#
#           /usr/bin/time --format="%U" ...
#
#         command that was used to measure compilation time of a particular $coq_opam_package
#         in a particular $iteration at the BASE of a given $coq_branch.
#
#     - $working_dir/$coq_opam_package.BASE.$iteration.perf
#
#         This file contains the output of the
#
#           perf stat -e instructions:u,cycles:u ...
#
#         command that was used to measure the total number of CPU instructions and CPU cycles
#         executed during the compilation of a particular $coq_opam_package in a particular $iteration
#         at the BASE of a given $coq_branch.
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

# Print the final results.
if [ -z "$installable_coq_opam_packages" ]; then
    # Tell the user that none of the OPAM-package(s) the user provided is/are installable.
    printf "INFO: "; print_singular_or_plural "the given OPAM-package" "none of the given OPAM-packages" $coq_opam_packages; echo ":"
    for coq_opam_package in $coq_opam_packages; do
        echo "- $coq_opam_package"
    done
    print_singular_or_plural "is not" "are" $coq_opam_packages; echo " installable."
else
    not_installable_coq_opam_packages=`comm -23 <(echo $coq_opam_packages | sed 's/ /\n/g' | sort | uniq) <(echo $installable_coq_opam_packages | sed 's/ /\n/g' | sort | uniq) | sed 's/\t//g'`
    echo "DEBUG: not_installable_coq_opam_packages = $not_installable_coq_opam_packages"

    if [ ! -z "$not_installable_coq_opam_packages" ]; then
        # Tell the user that some of the provided OPAM-package(s) is/are not installable.
        printf "INFO: the following OPAM-"; print_singular_or_plural "package" "packages" $not_installable_coq_opam_packages; echo ":"
        for coq_opam_package in $not_installable_coq_opam_packages; do
            echo "- $coq_opam_package"
        done
        printf "%s not installable.\n" $(print_singular_or_plural is are $not_installable_coq_opam_packages)
    fi

    echo "DEBUG: $program_path/render_results.ml "$working_dir" $num_of_iterations $head_long $base_long 0 user_time_pdiff $installable_coq_opam_packages"
    $program_path/shared/render_results.ml "$working_dir" $num_of_iterations $head_long $base_long 0 user_time_pdiff $installable_coq_opam_packages
fi
