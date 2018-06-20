#! /bin/bash -e

# :sy on
# :set expandtab
# :set smarttab
# :set tabstop=4
# :set shiftwidth=4

# ASSUMPTIONS:
# - camlp5 is installed and available in $PATH
# - ocamlfind is installed and available in $PATH
# - "ocaml*" binaries visible via $PATH
# - the OPAM packages, specified by the user, are topologically sorted wrt. to the dependency relationship.

r='\033[0m'          # reset (all attributes off)
b='\033[1m'          # bold
u='\033[4m'          # underline

number_of_processors=$(cat /proc/cpuinfo | grep '^processor *' | wc -l)

program_name="$0"
program_path=$(readlink -f "${program_name%/*}")
program_name="${program_name##*/}"
synopsys1="\t$b$program_name$r  [$b-h$r | $b--help$r]"
synopsys2="\t$b$program_name$r ${u}working_dir$r  ${u}new_ocaml_switch$r  ${u}new_coq_repository$r  ${u}new_coq_commit$r${r} \\\\\\n\t                                 ${u}new_coq_opam_archive_git_uri$r  ${u}new_coq_opam_archive_git_branch$r \\\\\\n\t                                 ${u}old_ocaml_switch$r  ${u}old_coq_repository$r  $r${u}old_coq_commit$r  ${u}num_of_iterations$r \\\\\\n\t                                 ${u}coq_opam_package_1$r [${u}coq_opam_package_2$r  ... [${u}coq_opam_package_N$r}] ... ]]"

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
    echo -e ${b}DESCRIPTION
    echo
    echo -e "$synopsys1"
    echo
    echo -e "\t\tPrint this help."
    echo
    echo -e "$synopsys2"
    echo
    echo -e "\t\tCompare the compilation times of given OPAM packages when we use two given versions of Coq."
    echo
    echo -e "\t\tHere:"
    echo -e "\t\t- ${u}working_dir$r determines the directory where all the necessary temporary files should be stored"
    echo -e "\t\t- ${u}new_coq_repository$r and ${u}new_coq_commit$r identifies the newer version of Coq"
    echo -e "\t\t- ${u}new_coq_opam_archive_git_{uri,branch}$r designates the git repository and the branch holding the definitions of OPAM packages"
    echo -e "\t\t- ${u}new_coq_opam_archive_git_branch$r is the branch (of the above repository) we want to use"
    echo -e "\t\t  that should be used with the ${u}new_coq_commit$r."
    echo -e "\t\t- ${u}old_coq_repository$r and ${u}old_coq_commit$r identifies the older version of Coq"
    echo -e "\t\t- ${u}num_of_iterations$r determines how many times each of the requested OPAM packages should be compiled"
    echo -e "\t\t  (with each of these two versions of Coq)."
    echo -e "\t\t- ${u}new_ocaml_switch$r and ${u}old_ocaml_switch$r determine the OCaml compiler used for each run"
    echo
    echo -e ${b}EXAMPLES$r
    echo
    echo -e "\t$b$program_name  /tmp https://github.com/gmalecha/coq.git  a0fc4cc \\"
    echo -e "\t                                  https://github.com/coq/opam-coq-archive.git  master \\"
    echo -e "\t                                  https://github.com/coq/coq.git  907db7e  1 \\"
    echo -e "\t                                  coq-hott coq-flocq coq-compcert coq-vst coq-geocoq coq-color \\"
    echo -e "\t                                  coq-fiat-crypto coq-fiat-parsers coq-unimath coq-sf \\"
    echo -e "\t                                  coq-mathcomp-ssreflect coq-iris coq-mathcomp-fingroup \\"
    echo -e "\t                                  coq-mathcomp-finmap coq-coquelicot coq-mathcomp-algebra \\"
    echo -e "\t                                  coq-mathcomp-solvable coq-mathcomp-field coq-mathcomp-character \\"
    echo -e "\t                                  coq-mathcomp-odd_order$r"
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
                echo "ERROR: unrecognized command-line argument \"$1\"." > /dev/stderr
                print_man_page_hint
                exit 1
                ;;
        esac
        ;;
    2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10)
        echo > /dev/stderr
        echo "ERROR: wrong number of arguments." > /dev/stderr
        print_man_page_hint
        exit 1
        ;;
    *)
        working_dir="$1"
        new_ocaml_switch="$2"
        new_coq_repository="$3"
        new_coq_commit="$4"
        new_coq_opam_archive_git_uri="$5"
        new_coq_opam_archive_git_branch="$6"
        old_ocaml_switch="$7"
        old_coq_repository="$8"
        old_coq_commit="$9"
        num_of_iterations="${10}"
        if echo "$num_of_iterations" | grep '^[1-9][0-9]*$' 2> /dev/null > /dev/null; then
            :
        else
            echo
            echo "ERROR: the third command-line argument \"$4\" is not a positive integer." > /dev/stderr
            print_man_page_hint
            exit 1
        fi
        shift 10
        coq_opam_packages=$@
        ;;
esac

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

# Detect the official Coq branch
#
# The computation below is based on the following assumptions:
# - 0986ee250818a5cb517b5e59fbd31e2cd1667775 is the oldest commit in "master" which is not present neither in "v8.7", nor in "v8.6", nor in "v8.5" branches.
# - 15edfc8f92477457bcefe525ce1cea160e4c6560 is the oldest commit in "master" which is not present neither in "v8.6", nor in "v8.5" branches.
# - bb43730ac876b8de79967090afa50f00858af6d5 is the oldest commit in "master" and "v8.6" which is not present in "v8.5".
# - 784d82dc1a709c4c262665a4cd4eb0b1bd1487a0 is the oldest commit that is present in "master" and "v8.6" and "v8.5" (but not in "v8.4").
#
# TODO: This is a hack.
#       We should probably rely on the results of the "git describe --tags" command.
#       We can't do that right now because the command
#       gives us misleading information in case of branches based "v8.7" and "master".)
if git log | grep 0986ee250818a5cb517b5e59fbd31e2cd1667775 > /dev/null; then
    official_coq_branch=master
elif git log | grep 15edfc8f92477457bcefe525ce1cea160e4c6560 > /dev/null; then
    official_coq_branch=v8.7
elif git log | grep bb43730ac876b8de79967090afa50f00858af6d5 > /dev/null; then
    official_coq_branch=v8.6
elif git log | grep 784d82dc1a709c4c262665a4cd4eb0b1bd1487a0 > /dev/null; then
    official_coq_branch=v8.5
else
    echo "ERROR: unrecognized Coq branch (neither \"v8.5\", nor \"v8.6\", nor \"trunk\")"
    exit 1
fi

echo DEBUG: official_coq_branch = $official_coq_branch

# Compute the OPAM version code corresponding to the compute name of the Coq branch
case $official_coq_branch in
    master)
        coq_opam_version=dev
        ;;
    v8.7)
        coq_opam_version=8.7.dev
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

echo DEBUG: coq_opam_version = $coq_opam_version

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
initial_opam_packages="camlp5 ocamlfind batteries"

echo n | opam init -v -j$number_of_processors --comp $new_ocaml_switch
echo $PATH
. "$OPAMROOT"/opam-init/init.sh
yes | opam install -v -j$number_of_processors $initial_opam_packages

new_coq_opam_archive_dir="$working_dir/new_coq_opam_archive"
git clone --depth 1 -b "$new_coq_opam_archive_git_branch" "$new_coq_opam_archive_git_uri" "$new_coq_opam_archive_dir"

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
