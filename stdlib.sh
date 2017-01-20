#! /bin/bash -e

# ASSUMPTIONS:
# - $working_directory exists and it is empty

program_name="$0"
program_path=$(readlink -f "${program_name%/*}")
program_name="${program_name##*/}"

r='\033[0m'          # reset (all attributes off)
b='\033[1m'          # bold
u='\033[4m'          # underline

synopsys1="\t$b$program_name$r  [$b-h$r | $b--help$r]"
synopsys2="\t$b$program_name$r  ${u}working_dir$r  ${u}coq_repository$r ${u}new_coq_tag$r  ${u}old_coq_tag$r  ${u}num_of_iterations$r"

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
    echo -e "\t\tClone Coq in a given ${u}working_dir$r."
    echo -e "\t\tMeasure the compilation time of the standard library both,"
    echo -e "\t\tfor the ${u}old_coq_tag$r as well as the ${u}new_coq_tag$r."
    echo -e "\t\tPrint the results."
    echo
    echo -e "\t\t${u}num_of_iterations$r determines how many times each of the standard library should be compiled."
    echo
    echo -e "\t\tAll the temporary files are created inside a given ${u}working_dir$r."
    echo
    echo -e "${b}EXAMPLES$r"
    echo
    echo -e "\t$b$program_name /tmp https://github.com/coq/coq.git V8.6 V8.5pl3 10$r"
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
    5)
        working_dir="$1"
        coq_repository="$2"
        new_coq_tag="$3"
        old_coq_tag="$4"
        if echo "$5" | grep '^[1-9][0-9]*$' 2> /dev/null > /dev/null; then
            num_of_iterations=$5
        else
            echo
            echo ERROR: the fourth command-line argument \"$5\" is not a positive integer.
            print_man_page_hint
            exit 1
        fi
        shift 4
        coq_opam_packages=$@
        ;;
    *)
        echo > /dev/stderr
        echo ERROR: wrong number of arguments. > /dev/stderr
        print_man_page_hint
        exit 1
        ;;
esac

# --------------------------------------------------------------------------------

number_of_processors=$(cat /proc/cpuinfo | grep '^processor *' | wc -l)

cd "$working_dir"
git clone $coq_repository coq
cd coq
for coq_tag in $old_coq_tag $new_coq_tag; do
    echo "DEBUG: coq_tag = $coq_tag"
    git clean -dfx
    git co -b $coq_tag $coq_tag
    for iteration in $(seq $num_of_iterations); do
        echo "DEBUG: iteration = $iteration"
        git clean -dfx
        ./configure -local
        make coqide -j$number_of_processors
        case $coq_tag in
            $old_coq_tag)
                old_or_new=OLD
                ;;
            $new_coq_tag)
                old_or_new=NEW
                ;;
        esac
        echo "DEBUG: old_or_new = $old_or_new"
        /usr/bin/time -o "$working_dir/stdlib.$old_or_new.$iteration.time" --format="%U" \
            perf stat -e instructions:u,cycles:u -o "$working_dir/stdlib.$old_or_new.$iteration.perf" \
            make theories -j1
    done
done

echo DEBUG: "$program_path"/shared/bench.ml "$working_dir" $num_of_iterations $new_coq_tag $old_coq_tag 0 package_name stdlib
"$program_path"/shared/bench.ml "$working_dir" $num_of_iterations $new_coq_tag $old_coq_tag 0 package_name stdlib
