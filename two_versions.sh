#! /bin/bash -e

# TODO:
# - avoid repeated compilation of camlp5
#   (use the same trick we used in "two_points_on_the_same_branch" script --- since Coq depends on camlp5,
#    it does not matter that camlp5 can be found in the path; OPAM will try to install it)

r='\033[0m'          # reset (all attributes off)
b='\033[1m'          # bold
u='\033[4m'          # underline

number_of_processors=$(cat /proc/cpuinfo | grep '^processor *' | wc -l)

program_name="$0"
program_path=$(readlink -f "${program_name%/*}")
program_name="${program_name##*/}"

synopsys1="\t$b$program_name$r  [$b-h$r | $b--help$r]"
synopsys2="\t$b$program_name$r  ${u}working_dir$r  ${u}newer_coq_version$r  ${u}older_coq_version$r  ${u}num_of_iterations$r  ${u}coq_opam_package_1$r [${u}coq_opam_package_2$r  ... [${u}coq_opam_package_N$r}] ... ]]"

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
    echo -e "\t\tIn a given ${u}working_dir$r create two new OPAM roots."
    echo -e "\t\tInstall a ${u}newer_coq_version$r to the first OPAM root"
    echo -e "\t\tand an ${u}older_coq_version$r to the second OPAM root."
    echo -e "\t\tFor each of these two Coq versions measure the compilation"
    echo -e "\t\tof all the given Coq OPAM packages."
    echo
    echo -e "\t\t${u}num_of_iterations$r determines how many times each of the Coq OPAM packages should be compiled."
    echo
    echo -e "\t\tAll the temporary files are created inside a given ${u}working_dir$r."
    echo
    echo -e "${b}EXAMPLES$r"
    echo
    echo -e "\t$b$program_name /tmp 8.6 8.5.3 10 coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect}$r"
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
        newer_coq_version="$2"
        older_coq_version="$3"
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

for coq_version in $older_coq_version $newer_coq_version; do
    echo DEBUG: coq_version = $coq_version
    export OPAMROOT="$working_dir/.opam"
    opam init --no-setup
    echo DEBUG: OPAMROOT = $OPAMROOT
    opam repo add coq-extra-dev https://coq.inria.fr/opam/extra-dev
    opam repo add coq-released https://coq.inria.fr/opam/released
    opam repo list
    yes | $program_path/shared/opam_install.sh coq.$coq_version -v -j$number_of_processors
    opam pin add coq $coq_version
    opam pin list
    mv $OPAMROOT $OPAMROOT.$coq_version
done

export OPAMROOT="$working_dir/.opam"

# Sort the opam packages
sorted_coq_opam_packages=$("${program_path}/sort-by-deps.sh" ${coq_opam_packages})
echo "DEBUG: sorted_coq_opam_packages = ${sorted_coq_opam_packages}"

for coq_opam_package in $sorted_coq_opam_packages; do
    echo DEBUG: coq_opam_package = $coq_opam_package

    # perform measurements with the $older_coq_version
    rm -r -f "$OPAMROOT"
    cp -r "$OPAMROOT.$older_coq_version" "$OPAMROOT"
    $program_path/shared/opam_install.sh $coq_opam_package -v -j$number_of_processors --deps-only -y
    for iteration in $(seq $num_of_iterations); do
        echo DEBUG: iteration = $iteration
        /usr/bin/time -o "$working_dir/$coq_opam_package.OLD.$iteration.time" --format="%U" \
            perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.OLD.$iteration.perf" \
            $program_path/shared/opam_install.sh $coq_opam_package -v -j1
        opam uninstall $coq_opam_package -v
    done

    # perform measurements with the $newer_coq_version
    rm -r -f "$OPAMROOT"
    cp -r "$OPAMROOT.$newer_coq_version" "$OPAMROOT"
    $program_path/shared/opam_install.sh $coq_opam_package -v -j$number_of_processors --deps-only -y
    for iteration in $(seq $num_of_iterations); do
        echo DEBUG: iteration = $iteration
        /usr/bin/time -o "$working_dir/$coq_opam_package.NEW.$iteration.time" --format="%U" \
            perf stat -e instructions:u,cycles:u -o "$working_dir/$coq_opam_package.NEW.$iteration.perf" \
            $program_path/shared/opam_install.sh $coq_opam_package -v -j1
        opam uninstall $coq_opam_package -v
    done
done

export OPAMROOT=
echo "DEBUG: ocamlfind = `which ocamlfind`"
echo "DEBUG: ocaml = `which ocaml`"
$program_path/shared/bench.ml $working_dir $num_of_iterations $newer_coq_version $older_coq_version 0 package_name $sorted_coq_opam_packages
