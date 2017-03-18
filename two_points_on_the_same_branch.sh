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
# - reuse the real *.opam file for Coq (we just need custom "url" file)
# - use this script to confirm/refute the prior measurements:
#   https://ci.inria.fr/coq/job/TEST10/13/console
# - add checks that user-provided HEAD and BASE values have proper chronological order
#   (i.e. HEAD is a more recent commit than BASE)
# - improve initial checks (whether all the things that we need exist)
# - camlp{4,5} ... probably we do not need the fake "camlp4" and "camlp5" packages
#   (there is a way to tell OPAM to use the camlp4/5 available on the system instead of compiling/installing it when some package depends on it)
# - describe the effect of that EXAMPLE command ... what kind of files are generated and what is their meaning
# - describe the effect of this command in general .... what kind of files are generated and what is their meaning
# - print a summary at the end
#   - for each package
#     - for each iteration
#       - user-time
#     - the minimum user-time
#     - the proportional variation
# - figure out some way to measure just the interpretation of "build" section
#   (not interpretation of the "url" file or "install" section in the *.opam file)
# - make experiments with working directory located in a ramdisk; can I get real-time speedup?
# - would it help if the tested package were downloaded via "opam source ..." and then added as a package to "custom-repo"?
# - figure out how to avoid measuring downloading of the actual OPAM package that is being done during "opam install"
#   (even when all its dependencies were already installed by "opam install --deps-only ...")
# - the stdout/stderr during the benchmarked compilation should probably go to /dev/null, no?
# - once we create v8.7 branch of Coq
#   - update:
#     - the "print_man_page" command
#     - the piece of code where we set the "official_coq_branch" variable
#     - the piece of code where we set the "coq_opam_version" variable
# - Consider the possibility to measure/monitor the load of the system.
#   This would give us hints about the reliability of the results we've obtained.
#   (We will know that when we measured and there was a lot of load, the results are not reliable.
#    On the other hand, if there was no load, we will know that the results should be meaningful.)

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
# - d0afde58b3320b65fc755cca5600af3b1bc9fa82 is the oldest commit in "trunk" and "v8.6" which is not present in "v8.5".
# - 784d82dc1a709c4c262665a4cd4eb0b1bd1487a0 is the oldest commit that is present in "trunk" and "v8.6" and "v8.5" (but not in "v8.4").
if git log | grep 15edfc8f92477457bcefe525ce1cea160e4c6560 > /dev/null; then
    official_coq_branch=trunk
elif git log | grep d0afde58b3320b65fc755cca5600af3b1bc9fa82 > /dev/null; then
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

echo DEBUG: coq_branch = $coq_branch
echo DEBUG: head = $head
echo DEBUG: base = $base

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

# Create a new OPAM-root to which we will install the HEAD of the designated branch of Coq

export OPAMROOT="$working_dir/.opam"

opam init --no-setup
opam repo add custom-opam-repo "$custom_opam_repo"
opam repo add coq-extra-dev https://coq.inria.fr/opam/extra-dev
opam repo add coq-released https://coq.inria.fr/opam/released
opam repo add coq-bench $HOME/git/coq-bench/opam
opam repo list
cd "$coq_dir"
git checkout $head
head_long=$(git log --pretty=%H | head -n 1)
echo DEBUG git commit for HEAD = $head_long
$program_path/shared/opam_install.sh coq.$coq_opam_version -v -j$number_of_processors
if [ ! $coq_opam_version = dev ]; then
  opam pin add coq $coq_opam_version
fi

mv "$OPAMROOT" "$OPAMROOT.NEW"

# --------------------------------------------------------------------------------

# Create a new OPAM-root to which we will install the BASE of the designated branch of Coq

export OPAMROOT="$working_dir/.opam"

opam init --no-setup
opam repo add custom-opam-repo "$custom_opam_repo"
opam repo add coq-extra-dev https://coq.inria.fr/opam/extra-dev
opam repo add coq-released https://coq.inria.fr/opam/released
opam repo add coq-bench $HOME/git/coq-bench/opam
opam repo list
cd "$coq_dir"
git checkout $base
base_long=$(git log --pretty=%H | head -n 1)
echo DEBUG git commit for BASE = $base_long
$program_path/shared/opam_install.sh coq.$coq_opam_version -v -j$number_of_processors
if [ ! $coq_opam_version = dev ]; then
  opam pin add coq $coq_opam_version
fi

mv "$OPAMROOT" "$OPAMROOT.OLD"

# --------------------------------------------------------------------------------

# Measure the compilation times of the specified OPAM packages
# - at the HEAD of the indicated branch
# - at the BASE of the indicated branch

export OPAMROOT="$working_dir/.opam"

for coq_opam_package in $coq_opam_packages; do
    echo DEBUG: coq_opam_package = $coq_opam_package
    # perform measurements for the HEAD of the branch (provided by the user)
    rm -r -f "$OPAMROOT"
    cp -r "$OPAMROOT.NEW" "$OPAMROOT"
    $program_path/shared/opam_install.sh $coq_opam_package -v -j$number_of_processors --deps-only -y
    for iteration in $(seq $num_of_iterations); do
        /usr/bin/time -o "$working_dir/$coq_opam_package.NEW.$iteration.time" --format="%U" \
            perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.NEW.$iteration.perf" \
            $program_path/shared/opam_install.sh $coq_opam_package -v -j1
        opam uninstall $coq_opam_package -v
    done

    # perform measurements for the BASE of the branch (provided by the user)
    rm -r -f "$OPAMROOT"
    cp -r "$OPAMROOT.OLD" "$OPAMROOT"
    $program_path/shared/opam_install.sh $coq_opam_package -v -j$number_of_processors --deps-only -y
    for iteration in $(seq $num_of_iterations); do
        /usr/bin/time -o "$working_dir/$coq_opam_package.OLD.$iteration.time" --format="%U" \
            perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.OLD.$iteration.perf" \
            $program_path/shared/opam_install.sh $coq_opam_package -v -j1
        opam uninstall $coq_opam_package -v
    done
done

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

echo DEBUG: $program_path/bench.ml "$working_dir" $num_of_iterations $head_long $base_long 0 user_time_pdiff $coq_opam_packages

$program_path/shared/bench.ml "$working_dir" $num_of_iterations $head_long $base_long 0 user_time_pdiff $coq_opam_packages
