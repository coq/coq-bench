#! /usr/bin/env ocaml

(* TODO:
   - swap the order of "instructions" and "cpu cycles"
     (the order in which we store them into the file)
     (the order in which we represent them in the memory)
*)

(* ASSUMPTIONS:
   - the 1-st command line argument (working directory):
     - designates an existing readable directory
     - which contains *.time and *.perf files produced by bench.sh script
   - the 2-nd command line argument (number of iterations):
     - is a positive integer
   - the 3-rd command line argument (minimal user time):
     - is a positive floating point number
   - the 4-th command line argument determines the name of the column according to which the resulting table will be sorted.
     Valid values are:
     - package_name
     - user_time_pdiff
   - the rest of the command line-arguments
     - are names of benchamarked Coq OPAM packages for which bench.sh script generated *.time and *.perf files
 *)

#use "topfind";;
#require "batteries";;
#print_depth 100000000;;
#print_length 100000000;;

open Batteries  (* M-x merlin-use batteries *)
open Printf
open Unix

;;
(* process command line paramters *)
assert (Array.length Sys.argv > 4);
let working_directory = Sys.argv.(1) in
let num_of_iterations = int_of_string Sys.argv.(2) in
let minimal_user_time = float_of_string Sys.argv.(3) in
let sorting_column = Sys.argv.(4) in
let coq_opam_packages = Sys.argv |> Array.to_list |> List.drop 5 in

(* ASSUMPTIONS:

   "working_directory" contains all the files produced by the following command:

      ./bench.sh $working_directory $coq_repository $coq_branch[:$head:$base] $num_of_iterations coq_opam_package_1 coq_opam_package_2 ...
*)

(* Run a given bash command;
   wait until it termines;
   check if its exit status is 0;
   return its whole stdout as a string. *)
let run cmd =
  match run_and_read cmd with
  | WEXITED 0, stdout -> stdout
  | _ -> assert false
in

(* parse the *.time and *.perf files *)

coq_opam_packages
|> List.map
     (fun package_name ->
       package_name,
       
       (* compilation_results_for_HEAD : (float * int * int) list *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".HEAD." ^ string_of_int iteration in

              (* HEAD_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* HEAD_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* HEAD_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string),

       (* compilation_results_for_BASE : (float * int * int) *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".BASE." ^ string_of_int iteration in

              (* BASE_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* BASE_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* BASE_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string))

(* [package_name, [HEAD_user_time, HEAD_instructions, HEAD_cycles]      , [BASE_user_time, BASE_instructions, BASE_cycles]     ]
 :  string      * (float         * int              * int        ) list * (float         * int              * int              ) list) list *)          

(* from the list of measured values, select just the minimal ones *)

|> List.map
     (fun ((package_name : string),
           (head_measurements : (float * int * int) list),
           (base_measurements : (float * int * int) list)) ->

       (* : string *)
       package_name,

       (* minimums_of_HEAD_measurements : float * int * int *)
       (
         (* minimal_HEAD_user_time : float *)
         head_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_HEAD_instructions : int *)
         head_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_HEAD_cycles : int *)
         head_measurements |> List.map Tuple3.third |> List.reduce min
       ),

       (* minimums_of_BASE_measurements : float * int * int *)
       (
         (* minimal_BASE_user_time : float *)
         base_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_BASE_instructions : int *)
         base_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_BASE_cycles : int *)
         base_measurements |> List.map Tuple3.third |> List.reduce min
       )
     )

(* [package_name, (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles) , (minimal_BASE_user_time, minimal_BASE_instructions, minimal_BASE_cycles)]
 : (string      * (float                 * int                      * int                ) * (float                       * int                            * int                      )) list *)

(* compute the "proportional differences in % of the HEAD measurement and the BASE measurement" of all measured values *)
|> List.map
     (fun (package_name,
           (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles as minimums_of_HEAD_measurements),
           (minimal_BASE_user_time, minimal_BASE_instructions, minimal_BASE_cycles as minimums_of_BASE_measurements)) ->
       package_name,
       minimums_of_HEAD_measurements,
       minimums_of_BASE_measurements,
       ((minimal_HEAD_user_time -. minimal_BASE_user_time) /. minimal_BASE_user_time *. 100.0,
        float_of_int (minimal_HEAD_instructions - minimal_BASE_instructions) /. float_of_int minimal_BASE_instructions *. 100.0,
        float_of_int (minimal_HEAD_cycles - minimal_BASE_cycles) /. float_of_int minimal_BASE_cycles *. 100.0))

(* [package_name,
    (minimal_HEAD_user_time, minimal_HEAD_instructions, minimal_HEAD_cycles),
    (minimal_BASE_user_time, minimal_BASE_instructions, minimal_BASE_cycles),
    (proportianal_difference_of_user_times, proportional_difference_of_instructions, proportional_difference_of_cycles)]

 : (string *
    (float * int * int) *
    (float * int * int) *
    (float * float * float)) list *)

(* sort the table with results *)
|> List.sort
     (match sorting_column with
      | "user_time_pdiff" ->
         (fun measurement1 measurement2 ->
           let get_user_time = Tuple4.fourth %> Tuple3.first in
           compare (get_user_time measurement1) (get_user_time measurement2))
      | "package_name" ->
         (fun measurement1 measurement2 ->
           compare (Tuple4.first measurement1) (Tuple4.first measurement2))
      | _ ->
         assert false
     )

(* Keep only measurements that took at least "minimal_user_time" (in seconds). *)

|> List.filter
     (fun (_, (minimal_HEAD_user_time,_,_), (minimal_BASE_user_time,_,_), _) ->
        minimal_user_time <= minimal_HEAD_user_time && minimal_user_time <= minimal_BASE_user_time)

(* Below we take the measurements and format them to stdout. *)

|> fun measurements ->
     let precision = 2 in

     (* the labels that we will print *)
     let package_name__label = "package_name" in
     let head__label = "HEAD" in
     let base__label = "BASE" in
     let proportional_difference__label = "PDIFF" in

     (* the lengths of labels that we will print *)
     let head__label__length = String.length head__label in
     let base__label__length = String.length base__label in
     let proportional_difference__label__length = String.length proportional_difference__label in

     (*
     measurements |> List.map Tuple4.first |> List.iter (printf "DEBUG: package_name = %s\n");
     measurements |> List.map (Tuple4.second %> Tuple3.first) |> List.iter (printf "DEBUG: head__user_time = %f\n");
     measurements |> List.map (Tuple4.second %> Tuple3.second) |> List.iter (printf "DEBUG: head__instructions = %d\n");
     measurements |> List.map (Tuple4.second %> Tuple3.third) |> List.iter (printf "DEBUG: head__cycles = %d\n");
     measurements |> List.map (Tuple4.third %> Tuple3.first) |> List.iter (printf "DEBUG: base__user_time = %f\n");
     measurements |> List.map (Tuple4.third %> Tuple3.second) |> List.iter (printf "DEBUG: base__instructions = %d\n");
     measurements |> List.map (Tuple4.third %> Tuple3.third) |> List.iter (printf "DEBUG: base__cycles = %d\n");
     measurements |> List.map (Tuple4.fourth %> Tuple3.first) |> List.iter (printf "DEBUG: proportional_difference__user_time = %f\n");
     measurements |> List.map (Tuple4.fourth %> Tuple3.second) |> List.iter (printf "DEBUG: proportional_difference__instructions = %f\n");
     measurements |> List.map (Tuple4.fourth %> Tuple3.third) |> List.iter (printf "DEBUG: proportional_difference__cycles = %f\n");
     *)

     (* widths of individual columns of the table *)
     let package_name__width = max (measurements |> List.map (Tuple4.first %> String.length) |> List.reduce max)
                                   (String.length package_name__label) in
     let head__user_time__width = max ((measurements |> List.map (Tuple4.second %> Tuple3.first)
                                        |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                      head__label__length in
     let head__instructions__width = max (measurements |> List.map (Tuple4.second %> Tuple3.second)
                                          |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                         head__label__length in
     let head__cycles__width = max (measurements |> List.map (Tuple4.second %> Tuple3.third)
                                    |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                   head__label__length in
     let base__user_time__width = max ((measurements |> List.map (Tuple4.third %> Tuple3.first)
                                        |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                      base__label__length in
     let base__instructions__width = max (measurements |> List.map (Tuple4.third %> Tuple3.second)
                                          |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                         base__label__length in
     let base__cycles__width = max (measurements |> List.map (Tuple4.third %> Tuple3.third)
                                    |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                   base__label__length
     in
     let proportional_difference__user_time__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple3.first %> abs_float) |> List.reduce max
                                                           |> log10 |> ceil |> int_of_float |> fun i -> if i <= 0 then 1 else i) + 2 + precision)
                                                         proportional_difference__label__length in
     let proportional_difference__instructions__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple3.second %> abs_float) |> List.reduce max
                                                              |> log10 |> ceil |> int_of_float |> fun i -> if i <= 0 then 1 else i) + 2 + precision)
                                                            proportional_difference__label__length in
     let proportional_difference__cycles__width = max ((measurements |> List.map (Tuple4.fourth %> Tuple3.third %> abs_float) |> List.reduce max
                                                        |> log10 |> ceil |> int_of_float |> fun i -> if i <= 0 then 1 else i) + 2 + precision)
                                                      proportional_difference__label__length in

     (* print the table *)

     let rec make_dashes = function
       | 0 -> ""
       | count -> "─" ^ make_dashes (pred count)
     in
     let vertical_separator left_glyph middle_glyph right_glyph = sprintf "%s─%s─%s─%s─%s─%s───%s─%s─%s─%s───%s─%s─%s─%s───%s\n"
       left_glyph
       (make_dashes package_name__width)
       middle_glyph
       (make_dashes head__user_time__width)
       (make_dashes base__user_time__width)
       (make_dashes proportional_difference__user_time__width)
       middle_glyph
       (make_dashes head__cycles__width)
       (make_dashes base__cycles__width)
       (make_dashes proportional_difference__cycles__width)
       middle_glyph
       (make_dashes head__instructions__width)
       (make_dashes base__instructions__width)
       (make_dashes proportional_difference__instructions__width)
       right_glyph
     in
     let center_string string width =
       let string_length = String.length string in
       let width = max width string_length in
       let left_hfill = (width - string_length) / 2 in
       let right_hfill = width - left_hfill - string_length in
       String.make left_hfill ' ' ^ string ^ String.make right_hfill ' '
     in
     printf "\n";
     print_string (vertical_separator "┌" "┬" "┐");
     "│" ^ String.make (1 + package_name__width + 1) ' ' ^ "│"
     ^ center_string "user time [s]" (1 +  head__user_time__width + 1 + base__user_time__width + 1 + proportional_difference__user_time__width + 3) ^ "│"
     ^ center_string "CPU cycles" (1 + head__cycles__width    + 1 + base__cycles__width    + 1 + proportional_difference__cycles__width + 3) ^ "│"
     ^ center_string "CPU instructions" (1 + head__instructions__width + 1 + base__instructions__width + 1 + proportional_difference__instructions__width + 3)
     ^ "│\n" |> print_string;
     printf "│%*s │ %*s│ %*s│ %*s│\n"
       (1 + package_name__width) ""
       (head__user_time__width      + 1 + base__user_time__width    + 1 + proportional_difference__user_time__width + 3) ""
       (head__cycles__width       + 1 + base__cycles__width       + 1 + proportional_difference__cycles__width + 3) ""
       (head__instructions__width + 1 + base__instructions__width + 1 + proportional_difference__instructions__width + 3) "";
     printf "│ %*s │ %*s %*s %*s   │ %*s %*s %*s   │ %*s %*s %*s   │\n"
       package_name__width package_name__label
       head__user_time__width head__label
       base__user_time__width base__label
       proportional_difference__user_time__width proportional_difference__label
       head__cycles__width head__label
       base__cycles__width base__label
       proportional_difference__cycles__width proportional_difference__label
       head__instructions__width head__label
       base__instructions__width base__label
       proportional_difference__instructions__width proportional_difference__label;
     measurements |> List.iter
         (fun (package_name,
               (head_user_time, head_instructions, head_cycles),
               (base_user_time, base_instructions, base_cycles),
               (proportional_difference__user_time, proportional_difference__instructions, proportional_difference__cycles)) ->
           print_string (vertical_separator "├" "┼" "┤");
           printf "│ %*s │ %*.*f %*.*f %+*.*f %% │ %*d %*d %+*.*f %% │ %*d %*d %+*.*f %% │\n"
             package_name__width package_name
             head__user_time__width precision head_user_time
             base__user_time__width precision base_user_time
             proportional_difference__user_time__width precision proportional_difference__user_time
             head__cycles__width head_cycles
             base__cycles__width base_cycles
             proportional_difference__cycles__width precision proportional_difference__cycles
             head__instructions__width head_instructions
             base__instructions__width base_instructions
             proportional_difference__instructions__width precision proportional_difference__instructions);

print_string (vertical_separator "└" "┴" "┘");
printf "

PDIFF ... proportional difference of the HEAD and BASE measurements
          (HEAD_measurement - BASE_measurement) / BASE_measurement * 100%%

";

(* TESTS:

   (* marelle1 *)

      (* ./bench.sh /tmp/a ~/git/coq/v8.6 v8.6:HEAD:d0afde58b3320b65fc755cca5600af3b1bc9fa82 10 coq-aac-tactics coq-abp coq-additions coq-ails coq-algebra coq-amm11262 coq-angles coq-area-method coq-atbr coq-automata coq-axiomatic-abp coq-bdds coq-bertrand coq-buchberger coq-canon-bdds coq-cantor coq-cats-in-zfc coq-ccs coq-cfgv coq-checker coq-chinese coq-circuits coq-classical-realizability coq-coalgebras coq-coinductive-examples coq-coinductive-reals coq-concat coq-constructive-geometry coq-containers coq-continuations coq-coq-in-coq coq-coqoban coq-counting coq-cours-de-coq coq-ctltctl coq-dblib coq-demos coq-dep-map coq-descente-infinie coq-dictionaries coq-distributed-reference-counting coq-domain-theory coq-ergo coq-euclidean-geometry coq-euler-formula coq-exact-real-arithmetic coq-exceptions coq-fairisle coq-fermat4 coq-finger-tree coq-firing-squad coq-float coq-founify coq-free-groups coq-fsets coq-fssec-model coq-functions-in-zfc coq-fundamental-arithmetics coq-gc coq-generic-environments coq-goedel coq-graph-basics coq-graphs coq-group-theory coq-groups coq-hardware coq-hedges coq-higman-cf coq-higman-nw coq-higman-s coq-historical-examples coq-hoare-tut coq-huffman coq-icharate coq-idxassoc coq-ieee754 coq-int-map coq-ipc coq-izf coq-jordan-curve-theorem coq-jprover coq-karatsuba coq-kildall coq-lambda coq-lambek coq-lazy-pcf coq-lc coq-lesniewski-mereology coq-lin-alg coq-ltl coq-maple-mode coq-markov coq-maths coq-matrices coq-mini-compiler coq-minic coq-miniml coq-mod-red coq-multiplier coq-mutual-exclusion coq-nfix coq-orb-stab coq-otway-rees coq-paco coq-paradoxes coq-param-pi coq-pautomata coq-persistent-union-find coq-pi-calc coq-pocklington coq-presburger coq-prfx coq-projective-geometry coq-propcalc coq-pts coq-ptsatr coq-ptsf coq-qarith coq-qarith-stern-brocot coq-quicksort-complexity coq-railroad-crossing coq-ramsey coq-random coq-rational coq-recursive-definition coq-reflexive-first-order coq-regexp coq-relation-extraction coq-rem coq-rsa coq-ruler-compass-geometry coq-schroeder coq-search-trees coq-semantics coq-shuffle coq-smc coq-square-matrices coq-stalmarck coq-streams coq-string coq-subst coq-sudoku coq-sum-of-two-square coq-tait coq-tarski-geometry coq-three-gap coq-topology coq-tortoise-hare-algorithm coq-traversable-fincontainer coq-tree-diameter coq-weak-up-to coq-zchinese coq-zf coq-zfc coq-zorns-lemma coq-zsearch-trees *)

     ./bench.ml inputs_for_formatting_tests/00 10 0 user_time_pdiff coq-aac-tactics coq-abp coq-additions coq-ails coq-algebra coq-amm11262 coq-angles coq-area-method coq-atbr coq-automata coq-axiomatic-abp coq-bdds coq-bertrand coq-buchberger coq-canon-bdds coq-cantor coq-cats-in-zfc coq-ccs coq-cfgv coq-checker coq-chinese coq-circuits coq-classical-realizability coq-coalgebras coq-coinductive-examples coq-coinductive-reals coq-concat coq-constructive-geometry coq-containers coq-continuations coq-coq-in-coq coq-coqoban coq-counting coq-cours-de-coq coq-ctltctl coq-dblib coq-demos coq-dep-map coq-descente-infinie coq-dictionaries coq-distributed-reference-counting coq-domain-theory coq-ergo coq-euclidean-geometry coq-euler-formula coq-exact-real-arithmetic coq-exceptions coq-fairisle coq-fermat4 coq-finger-tree coq-firing-squad coq-float coq-founify coq-free-groups coq-fsets coq-fssec-model coq-functions-in-zfc coq-fundamental-arithmetics coq-gc coq-generic-environments coq-goedel coq-graph-basics coq-graphs coq-group-theory coq-groups coq-hardware coq-hedges coq-higman-cf coq-higman-nw coq-higman-s coq-historical-examples coq-hoare-tut coq-huffman coq-icharate coq-idxassoc coq-ieee754 coq-int-map coq-ipc coq-izf coq-jordan-curve-theorem coq-jprover coq-karatsuba coq-kildall coq-lambda coq-lambek coq-lazy-pcf coq-lc coq-lesniewski-mereology coq-lin-alg coq-ltl coq-maple-mode coq-markov coq-maths coq-matrices coq-mini-compiler coq-minic coq-miniml coq-mod-red coq-multiplier coq-mutual-exclusion coq-nfix coq-orb-stab coq-otway-rees coq-paco coq-paradoxes coq-param-pi coq-pautomata coq-persistent-union-find coq-pi-calc coq-pocklington coq-presburger coq-prfx coq-projective-geometry coq-propcalc coq-pts coq-ptsatr coq-ptsf coq-qarith coq-qarith-stern-brocot coq-quicksort-complexity coq-railroad-crossing coq-ramsey coq-random coq-rational coq-recursive-definition coq-reflexive-first-order coq-regexp coq-relation-extraction coq-rem coq-rsa coq-ruler-compass-geometry coq-schroeder coq-search-trees coq-semantics coq-shuffle coq-smc coq-square-matrices coq-stalmarck coq-streams coq-string coq-subst coq-sudoku coq-sum-of-two-square coq-tait coq-tarski-geometry coq-three-gap coq-topology coq-tortoise-hare-algorithm coq-traversable-fincontainer coq-tree-diameter coq-weak-up-to coq-zchinese coq-zf coq-zfc coq-zorns-lemma coq-zsearch-trees

     ┌────────────────────────────────────┬────────────────────────┬──────────────────────────────────────┬──────────────────────────────────────┐
     │                                    │     user time [s]      │              CPU cycles              │           CPU instructions           │
     │                                    │                        │                                      │                                      │
     │                       package_name │   HEAD   BASE  PDIFF   │          HEAD          BASE  PDIFF   │          HEAD          BASE  PDIFF   │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-finger-tree │  72.97 130.48 -44.08 % │  271966246355  490763196143 -44.58 % │  270054241897  469074434129 -42.43 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-paco │  42.60  50.98 -16.44 % │  159051246629  190513166596 -16.51 % │  194540025966  262863995764 -25.99 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │            coq-qarith-stern-brocot │  76.58  90.31 -15.20 % │  282683561751  335893497470 -15.84 % │  323853260323  420899109162 -23.06 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-goedel │  76.95  81.12  -5.14 % │  284774471596  300980725143  -5.38 % │  339000256424  366414217199  -7.48 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-regexp │   7.58   7.92  -4.29 % │   27642287194   27840983987  -0.71 % │   33886413296   34006774127  -0.35 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-ctltctl │   6.26   6.48  -3.40 % │   22521582218   22545408106  -0.11 % │   28671278936   28738238224  -0.23 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-lazy-pcf │   6.98   7.18  -2.79 % │   25046211134   25141115274  -0.38 % │   31652405843   31740669969  -0.28 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-rsa │   7.52   7.72  -2.59 % │   26966923768   27121326981  -0.57 % │   32532825717   32593922111  -0.19 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-free-groups │   5.36   5.49  -2.37 % │   19224341093   19222767262  +0.01 % │   24978555909   24995518859  -0.07 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-circuits │   8.29   8.49  -2.36 % │   29776336117   29939204952  -0.54 % │   36286965955   36445828463  -0.44 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-algebra │  22.36  22.82  -2.02 % │   81304756987   84307777031  -3.56 % │   94677365829   98944903454  -4.31 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-otway-rees │   7.80   7.96  -2.01 % │   28226708490   28338499233  -0.39 % │   35760724993   35881448612  -0.34 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-maple-mode │  12.71  12.97  -2.00 % │   45094769650   45766207034  -1.47 % │   47082404325   47606440634  -1.10 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-additions │  11.70  11.93  -1.93 % │   42329705180   42774191681  -1.04 % │   50287942021   50669346629  -0.75 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-orb-stab │   6.35   6.47  -1.85 % │   22878980691   22857720215  +0.09 % │   28803062826   28831111576  -0.10 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │               coq-functions-in-zfc │   5.86   5.97  -1.84 % │   20998765025   21446999172  -2.09 % │   26270936564   26446117570  -0.66 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-karatsuba │  10.92  11.12  -1.80 % │   39183450952   39424657634  -0.61 % │   49632926067   49647895048  -0.03 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-domain-theory │   7.28   7.41  -1.75 % │   25978969742   26045904211  -0.26 % │   31827998588   31844031990  -0.05 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-pocklington │  10.53  10.71  -1.68 % │   37795546287   38177117257  -1.00 % │   44102437856   44355218932  -0.57 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-zorns-lemma │  11.18  11.37  -1.67 % │   40157053349   40471676403  -0.78 % │   46722563578   46956529586  -0.50 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-int-map │  12.19  12.38  -1.53 % │   43515783389   44056650931  -1.23 % │   48954661252   49273891546  -0.65 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-chinese │   8.60   8.73  -1.49 % │   30237857563   30461784157  -0.74 % │   37003470605   37182756525  -0.48 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-pts │  12.62  12.81  -1.48 % │   46232143841   45940323534  +0.64 % │   51341461650   50990439114  +0.69 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │          coq-exact-real-arithmetic │  21.10  21.37  -1.26 % │   76163239081   76542783345  -0.50 % │   83424116617   83713808895  -0.35 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-huffman │  17.36  17.58  -1.25 % │   62363323917   62583833132  -0.35 % │   69522035122   69740909271  -0.31 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-sudoku │  39.06  39.50  -1.11 % │  144889760838  146209997877  -0.90 % │  202063233004  202017552584  +0.02 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-qarith │   7.45   7.53  -1.06 % │   26554339310   26615880921  -0.23 % │   32317814006   32523485512  -0.63 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-bdds │  25.85  26.12  -1.03 % │   92673334168   93880518130  -1.29 % │  104934755429  105505782103  -0.54 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-streams │   5.77   5.83  -1.03 % │   20386001536   20544280978  -0.77 % │   26355759682   26395766780  -0.15 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │        coq-classical-realizability │  73.14  73.84  -0.95 % │  272748168760  276129313025  -1.22 % │  332693289876  339230242580  -1.93 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │           coq-recursive-definition │   8.86   8.94  -0.89 % │   31045079821   31296303430  -0.80 % │   38400871911   38564401725  -0.42 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-pautomata │  13.84  13.96  -0.86 % │   49210753721   49801419365  -1.19 % │   57061219208   57503538729  -0.77 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-ieee754 │   7.30   7.36  -0.82 % │   25884894587   26076422814  -0.73 % │   32421569340   32549878353  -0.39 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-canon-bdds │  10.04  10.12  -0.79 % │   36099046093   36345251369  -0.68 % │   42003906082   42158115909  -0.37 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-three-gap │  10.14  10.22  -0.78 % │   36390124751   36471433888  -0.22 % │   41604122869   41685131638  -0.19 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │ coq-distributed-reference-counting │  38.81  39.10  -0.74 % │  139100483910  140669691852  -1.12 % │  148336025480  149158223963  -0.55 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-ccs │   5.37   5.41  -0.74 % │   19099907985   19213126451  -0.59 % │   24860108218   24868353954  -0.03 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-paradoxes │   5.76   5.80  -0.69 % │   20368384805   20413651210  -0.22 % │   26178677019   26206785608  -0.11 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-topology │  27.51  27.70  -0.69 % │   99484214484   99380877589  +0.10 % │  109480635881  109143618186  +0.31 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-automata │   8.78   8.84  -0.68 % │   31440324436   31572927981  -0.42 % │   36847934231   36970731562  -0.33 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-higman-s │   7.84   7.89  -0.63 % │   28207060449   28134623669  +0.26 % │   34469759604   34540548274  -0.20 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-jprover │   6.57   6.61  -0.61 % │   22631663384   22729184642  -0.43 % │   29865408299   29878656808  -0.04 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-minic │   8.99   9.04  -0.55 % │   31720914164   32073508494  -1.10 % │   38770974576   39002544775  -0.59 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-hedges │   7.58   7.62  -0.52 % │   27202264990   27171230487  +0.11 % │   32552939967   32370884934  +0.56 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-axiomatic-abp │   8.86   8.90  -0.45 % │   31991699839   32125993965  -0.42 % │   38001780977   37943091652  +0.15 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-fairisle │  46.25  46.44  -0.41 % │  168444295537  168903835815  -0.27 % │  206100176339  206548022259  -0.22 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-lambek │   7.80   7.83  -0.38 % │   27956957915   28125105189  -0.60 % │   34059603568   34189750502  -0.38 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-nfix │   5.59   5.61  -0.36 % │   19534749534   19571029182  -0.19 % │   25553227776   25576146697  -0.09 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-mini-compiler │   5.71   5.73  -0.35 % │   20008135002   20089678192  -0.41 % │   25819552111   25829541316  -0.04 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-lambda │   9.07   9.10  -0.33 % │   32283349863   32397448111  -0.35 % │   39204433748   39296522362  -0.23 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-angles │   9.10   9.13  -0.33 % │   33053731283   32788225693  +0.81 % │   37569616063   37413764499  +0.42 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │            coq-relation-extraction │   6.14   6.16  -0.32 % │   21021513973   21053744983  -0.15 % │   27593210959   27614190794  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-markov │   6.48   6.50  -0.31 % │   23104750645   23145903188  -0.18 % │   28685515990   28631824598  +0.19 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-tree-diameter │   7.66   7.68  -0.26 % │   27577720296   27272051236  +1.12 % │   33008062689   32702542124  +0.93 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-founify │   7.79   7.81  -0.26 % │   27427692835   27498042605  -0.26 % │   33336869179   33410061581  -0.22 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-continuations │   9.05   9.07  -0.22 % │   32076482779   32218600273  -0.44 % │   38504461588   38663338867  -0.41 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-coalgebras │  10.26  10.28  -0.19 % │   36858636979   36844345732  +0.04 % │   44868506522   44934468080  -0.15 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-checker │   5.26   5.27  -0.19 % │   18490959379   18474545507  +0.09 % │   24350328551   24370835843  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-exceptions │   5.47   5.48  -0.18 % │   19200457581   19226573830  -0.14 % │   25143114449   25169352333  -0.10 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │        coq-fundamental-arithmetics │  11.00  11.02  -0.18 % │   39630775341   39551129317  +0.20 % │   45903307240   45817763670  +0.19 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │               coq-mutual-exclusion │   5.73   5.74  -0.17 % │   19974525201   20050913885  -0.38 % │   25882033032   25908873316  -0.10 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-rational │  11.78  11.80  -0.17 % │   41190473328   41594588230  -0.97 % │   50350057165   50677137006  -0.65 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │           coq-lesniewski-mereology │   6.22   6.23  -0.16 % │   22163441051   22183178814  -0.09 % │   27460348695   27460581690  -0.00 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                   coq-group-theory │   7.39   7.40  -0.14 % │   26274576736   26439662761  -0.62 % │   32720377911   32849553979  -0.39 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                   coq-firing-squad │  12.36  12.37  -0.08 % │   43581690520   43589867750  -0.02 % │   49368962250   49348611495  +0.04 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-buchberger │  29.06  29.08  -0.07 % │  106365152598  105530113721  +0.79 % │  116559491003  115586661014  +0.84 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-aac-tactics │  11.28  11.28  +0.00 % │   40368576119   40216989212  +0.38 % │   45326905242   45290671900  +0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │          coq-constructive-geometry │   5.78   5.78  +0.00 % │   20318620754   20347405253  -0.14 % │   26018244367   26044185178  -0.10 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-coqoban │   6.46   6.46  +0.00 % │   22560326013   22593854552  -0.15 % │   28975251416   28989789318  -0.05 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                   coq-cours-de-coq │   6.68   6.68  +0.00 % │   23595480725   23778670005  -0.77 % │   29964506372   30041315412  -0.26 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │            coq-historical-examples │   5.67   5.67  +0.00 % │   19986665410   20077767481  -0.45 % │   25846618411   25884478562  -0.15 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-cats-in-zfc │  91.13  91.12  +0.01 % │  339997256073  340787492751  -0.23 % │  390278791024  388741400368  +0.40 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │           coq-quicksort-complexity │  54.09  54.06  +0.06 % │  198730639052  198755896946  -0.01 % │  212056451551  213321958583  -0.59 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-dep-map │  10.80  10.79  +0.09 % │   38378617083   38805289045  -1.10 % │   44017490255   44406209390  -0.88 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-graphs │   8.62   8.61  +0.12 % │   30740707818   30546328791  +0.64 % │   36257240984   35994513796  +0.73 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │              coq-railroad-crossing │   7.16   7.15  +0.14 % │   25417588546   25380956445  +0.14 % │   31166508918   31151986424  +0.05 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-higman-nw │   6.14   6.13  +0.16 % │   21259499940   21337328164  -0.36 % │   27349170762   27400406825  -0.19 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-icharate │  23.88  23.84  +0.17 % │   85964050460   86425368388  -0.53 % │   98250693337   98618243413  -0.37 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │               coq-descente-infinie │   5.55   5.54  +0.18 % │   19481721243   19472584604  +0.05 % │   25363296937   25371486851  -0.03 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-schroeder │   5.46   5.45  +0.18 % │   19398308822   19411582858  -0.07 % │   25346148795   25376886800  -0.12 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-rem │   5.27   5.26  +0.19 % │   18658608815   18678358049  -0.11 % │   24579452687   24598166533  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-groups │   5.25   5.24  +0.19 % │   18461034068   18479013739  -0.10 % │   24300873569   24317297553  -0.07 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │          coq-reflexive-first-order │  11.99  11.96  +0.25 % │   43025010201   42678142519  +0.81 % │   49209051528   48939441353  +0.55 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                             coq-zf │   7.77   7.75  +0.26 % │   27478829498   27440310991  +0.14 % │   32978225615   32924470502  +0.16 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │           coq-generic-environments │   7.19   7.17  +0.28 % │   25684107134   25812795865  -0.50 % │   30731797187   30778366284  -0.15 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-amm11262 │  10.29  10.26  +0.29 % │   36967393276   36860419994  +0.29 % │   42870043074   42910474463  -0.09 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-smc │  21.98  21.90  +0.37 % │   79499174275   79191494396  +0.39 % │   85820862494   85532311041  +0.34 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-containers │ 159.88 159.28  +0.38 % │  597175584831  594013678440  +0.53 % │  587930783747  594730609231  -1.14 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-abp │   7.61   7.58  +0.40 % │   27146831074   27268752520  -0.45 % │   33221904187   33222959396  -0.00 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-string │   7.14   7.11  +0.42 % │   24473543156   24657850466  -0.75 % │   30845100681   30926917515  -0.26 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-zchinese │   6.96   6.93  +0.43 % │   24139884198   24150200048  -0.04 % │   30125727263   30186263045  -0.20 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-stalmarck │  42.88  42.68  +0.47 % │  154794270263  154942817572  -0.10 % │  172665294600  172517303924  +0.09 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-idxassoc │   5.81   5.78  +0.52 % │   20177491842   20205979407  -0.14 % │   26066761937   26088640090  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │        coq-tortoise-hare-algorithm │   5.62   5.59  +0.54 % │   19863056234   19840596277  +0.11 % │   25722304224   25744017340  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-cfgv │ 111.95 111.32  +0.57 % │  419054399506  417113506972  +0.47 % │  439854790642  440510259050  -0.15 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-kildall │  35.17  34.97  +0.57 % │  126039793638  125792603832  +0.20 % │  142147410509  141447664967  +0.49 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-hardware │  13.87  13.79  +0.58 % │   49215873149   49810651571  -1.19 % │   57657982834   58101740403  -0.76 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-hoare-tut │   7.18   7.13  +0.70 % │   25285353156   25097366816  +0.75 % │   30567845119   30491052252  +0.25 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-shuffle │   5.73   5.69  +0.70 % │   19934154201   19943509727  -0.05 % │   25769640650   25789073082  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                   coq-search-trees │   7.05   7.00  +0.71 % │   24653441146   24693955430  -0.16 % │   30987785580   31026478761  -0.12 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │           coq-coinductive-examples │   5.50   5.46  +0.73 % │   19423284132   19447849379  -0.13 % │   25352256960   25381917381  -0.12 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-ramsey │   5.34   5.30  +0.75 % │   18668985363   18800258714  -0.70 % │   24597891546   24616445096  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │              coq-sum-of-two-square │  20.96  20.79  +0.82 % │   76720699038   76231876419  +0.64 % │   81608268148   81062106621  +0.67 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-matrices │   7.37   7.31  +0.82 % │   25998514126   26036546121  -0.15 % │   32015971375   32044633072  -0.09 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-multiplier │   5.91   5.86  +0.85 % │   20521816901   20567631055  -0.22 % │   26385428572   26414910230  -0.11 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │       coq-traversable-fincontainer │   7.06   7.00  +0.86 % │   25313887922   25399067394  -0.34 % │   31783924858   31808363555  -0.08 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-ipc │  16.40  16.26  +0.86 % │   58904513475   58712966760  +0.33 % │   65260421586   65180817251  +0.12 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-ltl │   5.68   5.63  +0.89 % │   19974075610   20001552424  -0.14 % │   25890524975   25927227044  -0.14 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-param-pi │   7.85   7.77  +1.03 % │   27808622719   27549065722  +0.94 % │   33089545967   32870650361  +0.67 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-weak-up-to │   6.76   6.69  +1.05 % │   24200014444   24078800905  +0.50 % │   29383757354   29348901060  +0.12 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-izf │   5.76   5.70  +1.05 % │   20424668201   20358687518  +0.32 % │   26163810046   26200490820  -0.14 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-miniml │   6.65   6.58  +1.06 % │   23787849620   23449339462  +1.44 % │   29582173565   29207121847  +1.28 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-concat │  12.65  12.51  +1.12 % │   45297987191   45624853948  -0.72 % │   53504708742   53818637692  -0.58 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-semantics │  26.92  26.62  +1.13 % │   98581870373   97166685355  +1.46 % │  105069235585  103740574027  +1.28 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-ptsf │  14.88  14.71  +1.16 % │   54817544402   54159702735  +1.21 % │   61396057792   61267639657  +0.21 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-euler-formula │  14.57  14.40  +1.18 % │   53225997077   52835677585  +0.74 % │   56938795734   56621128514  +0.56 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-demos │   6.65   6.57  +1.22 % │   23654160971   23693397847  -0.17 % │   30282112841   30287644318  -0.02 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                coq-square-matrices │   5.54   5.47  +1.28 % │   19275238082   19358537885  -0.43 % │   25204960883   25232372108  -0.11 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-ergo │ 198.85 196.32  +1.29 % │  741954563896  733959689376  +1.09 % │  802396189639  793709978321  +1.09 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-dblib │  15.62  15.42  +1.30 % │   56882539501   55917827073  +1.73 % │   63135618037   62347901752  +1.26 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                             coq-lc │   7.72   7.62  +1.31 % │   27747578870   27560793027  +0.68 % │   32955675940   32779010075  +0.54 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-propcalc │   7.66   7.56  +1.32 % │   27244848817   27236138979  +0.03 % │   33122178245   33257267977  -0.41 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-lin-alg │ 115.45 113.91  +1.35 % │  426696099533  420904284623  +1.38 % │  600091835292  598593956107  +0.25 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-cantor │  23.79  23.47  +1.36 % │   86191991325   85903218572  +0.34 % │   93387119174   93607349050  -0.24 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-maths │   7.77   7.66  +1.44 % │   27817363247   27519581957  +1.08 % │   32843530851   32611972082  +0.71 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-prfx │  13.42  13.23  +1.44 % │   47475412263   48126563698  -1.35 % │   56355026490   56964928166  -1.07 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-coq-in-coq │  17.78  17.52  +1.48 % │   64110274515   63277963338  +1.32 % │   68683806403   68124480867  +0.82 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-bertrand │  29.65  29.18  +1.61 % │  108892627204  107233697384  +1.55 % │  120904914273  118971963274  +1.62 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                      coq-higman-cf │   6.76   6.65  +1.65 % │   23940380033   23340248208  +2.57 % │   29174917566   28707895752  +1.63 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-float │  50.86  49.98  +1.76 % │  186119858728  182374191672  +2.05 % │  178412418103  176060020977  +1.34 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-ptsatr │  33.82  33.22  +1.81 % │  125298254026  121856582146  +2.82 % │  132489105359  136094936529  -2.65 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                         coq-random │  31.43  30.87  +1.81 % │  115782424557  112969993442  +2.49 % │  104785365209  103374609877  +1.36 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-subst │  14.11  13.84  +1.95 % │   51045748787   50392849247  +1.30 % │   51909931723   51700880185  +0.40 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │           coq-jordan-curve-theorem │ 290.85 285.10  +2.02 % │ 1094549387157 1074025247212  +1.91 % │ 1134500552326 1101855748875  +2.96 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-mod-red │  22.15  21.68  +2.17 % │   81243638274   80090950345  +1.44 % │   93159221281   91888196499  +1.38 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │         coq-ruler-compass-geometry │  29.18  28.56  +2.17 % │  107217919303  103887832026  +3.21 % │  107624745402  103766148118  +3.72 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                   coq-graph-basics │  10.17   9.95  +2.21 % │   35330493290   35635147225  -0.85 % │   41816408634   42012379674  -0.47 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-atbr │ 245.53 240.17  +2.23 % │  921752545181  902204148843  +2.17 % │  867560576902  858511383645  +1.05 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                     coq-presburger │  26.32  25.67  +2.53 % │   95178460611   93055075502  +2.28 % │   97518469917   95706908775  +1.89 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-fermat4 │  15.80  15.38  +2.73 % │   57068843385   55841483921  +2.20 % │   63088069912   61932757953  +1.87 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-fssec-model │  22.52  21.78  +3.40 % │   82165891010   79981994860  +2.73 % │   92242939460   90147865429  +2.32 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                  coq-zsearch-trees │   7.10   6.85  +3.65 % │   24804446144   24090373677  +2.96 % │   30064571979   29602594451  +1.56 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                   coq-dictionaries │   6.95   6.70  +3.73 % │   24623348852   23966061314  +2.74 % │   30064249733   29605588356  +1.55 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                            coq-zfc │   8.27   7.97  +3.76 % │   28807566908   28789562114  +0.06 % │   33913988527   33918595799  -0.01 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │             coq-euclidean-geometry │  42.27  40.72  +3.81 % │  151834596607  147031754723  +3.27 % │  165662306327  158153783034  +4.75 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │              coq-coinductive-reals │  94.00  90.25  +4.16 % │  349744185902  335042785589  +4.39 % │  377625808183  362374298764  +4.21 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                          coq-fsets │ 137.05 130.84  +4.75 % │  512651513884  488432005242  +4.96 % │  518297327765  495941758326  +4.51 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                       coq-counting │   5.63   5.37  +4.84 % │   19071581140   19071180596  +0.00 % │   25043669167   25058111934  -0.06 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-ails │  20.12  19.19  +4.85 % │   73682061736   70696704272  +4.22 % │   83595188350   78920690900  +5.92 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                           coq-tait │  23.59  22.40  +5.31 % │   86106021216   81644280234  +5.46 % │   91371573939   87336119935  +4.62 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                    coq-area-method │ 515.66 488.00  +5.67 % │ 1942382306279 1837215250051  +5.72 % │ 2059418979531 1970064979033  +4.54 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │            coq-projective-geometry │ 614.18 579.91  +5.91 % │ 2313917165115 2185951692031  +5.85 % │ 2395940884871 2238980333826  +7.01 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                coq-tarski-geometry │  42.98  37.21 +15.51 % │  160605544905  137757805131 +16.59 % │  149994594080  131080392559 +14.43 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                        coq-pi-calc │  64.16  51.23 +25.24 % │  239839797623  190515814705 +25.89 % │  263261920164  212297809040 +24.01 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │                             coq-gc │ 140.07 108.41 +29.20 % │  522007828830  404620015539 +29.01 % │  465437246854  373224624458 +24.71 % │
     ├────────────────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
     │          coq-persistent-union-find │  48.21  28.24 +70.72 % │  180815018920  105128433939 +71.99 % │  181435152299  116933614986 +55.16 % │
     └────────────────────────────────────┴────────────────────────┴──────────────────────────────────────┴──────────────────────────────────────┘
     
     
     PDIFF ... proportional difference of the HEAD and BASE measurements
               (HEAD_measurement - BASE_measurement) / BASE_measurement * 100%
*)
