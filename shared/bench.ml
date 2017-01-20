#! /usr/bin/env ocaml

(* TODO:
   - give this script some more appropriate name
   - remove "filtering" of measurements that are two short ... this did not actually help
   - refactor and share the code between the two "bench.ml" scripts
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

printf "DEBUG 0\n";

(* process command line paramters *)
assert (Array.length Sys.argv > 5);
let working_directory = Sys.argv.(1) in
let num_of_iterations = int_of_string Sys.argv.(2) in
let new_coq_version = Sys.argv.(3) in
let old_coq_version = Sys.argv.(4) in
let minimal_user_time = float_of_string Sys.argv.(5) in
let sorting_column = Sys.argv.(6) in
let coq_opam_packages = Sys.argv |> Array.to_list |> List.drop 7 in

printf "DEBUG 1: working_directory = %s\n" working_directory;
printf "DEBUG 1: num_of_iterations = %d\n" num_of_iterations;
printf "DEBUG 1: new_coq_version = %s\n" new_coq_version;
printf "DEBUG 1: old_coq_version = %s\n" old_coq_version;
printf "DEBUG 1: minimal_user_time = %f\n" minimal_user_time;
printf "DEBUG 1: sorting_column = %s\n" sorting_column;
List.iteri (printf "DEBUG 1: coq_opam_package[%d] = %s\n") coq_opam_packages;

(* ASSUMPTIONS:

   "working_dir" contains all the files produced by the following command:

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
       
       (* compilation_results_for_NEW : (float * int * int) list *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".NEW." ^ string_of_int iteration in

              (* NEW_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* NEW_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* NEW_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string),

       (* compilation_results_for_OLD : (float * int * int) list *)
       List.init num_of_iterations succ
       |> List.map
            (fun iteration ->
              let command_prefix = "cat " ^ working_directory ^ "/" ^ package_name ^ ".OLD." ^ string_of_int iteration in

              (* OLD_user_time : float *)
              command_prefix ^ ".time" |> run |> String.rchop ~n:1 |> float_of_string,

              (* OLD_instructions : int *)
              command_prefix ^ ".perf | grep instructions:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string,

              (* OLD_cycles : int *)
              command_prefix ^ ".perf | grep cycles:u | awk '{print $1}' | sed 's/,//g'"
              |> run |> String.rchop ~n:1 |> int_of_string))

(* [package_name, [NEW_user_time, NEW_instructions, NEW_cycles]      , [OLD_user_time, OLD_instructions, OLD_cycles]     ]
 : (string      * (float        * int             * int       ) list * (float        * int             * int             ) list) list *)

(* from the list of measured values, select just the minimal ones *)

|> List.map
     (fun ((package_name : string),
           (new_measurements : (float * int * int) list),
           (old_measurements : (float * int * int) list)) ->

       (* : string *)
       package_name,

       (* minimums_of_NEW_measurements : float * int * int *)
       (
         (* minimal_NEW_user_time : float *)
         new_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_NEW_instructions : int *)
         new_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_NEW_cycles : int *)
         new_measurements |> List.map Tuple3.third |> List.reduce min
       ),

       (* minimums_of_OLD_measurements : float * int * int *)
       (
         (* minimal_OLD_user_time : float *)
         old_measurements |> List.map Tuple3.first |> List.reduce min,

         (* minimal_OLD_instructions : int *)
         old_measurements |> List.map Tuple3.second |> List.reduce min,

         (* minimal_OLD_cycles : int *)
         old_measurements |> List.map Tuple3.third |> List.reduce min
       )
     )

(* [package_name, (minimal_NEW_user_time, minimal_NEW_instructions, minimal_NEW_cycles) , (minimal_OLD_user_time, minimal_OLD_instructions, minimal_OLD_cycles)]
 : (string      * (float                * int                     * int               ) * (float                * int                     * int                      )) list *)

(* compute the "proportional differences in % of the NEW measurement and the OLD measurement" of all measured values *)
|> List.map
     (fun (package_name,
           (minimal_NEW_user_time, minimal_NEW_instructions, minimal_NEW_cycles as minimums_of_NEW_measurements),
           (minimal_OLD_user_time, minimal_OLD_instructions, minimal_OLD_cycles as minimums_of_OLD_measurements)) ->
       package_name,
       minimums_of_NEW_measurements,
       minimums_of_OLD_measurements,
       ((minimal_NEW_user_time -. minimal_OLD_user_time) /. minimal_OLD_user_time *. 100.0,
        float_of_int (minimal_NEW_instructions - minimal_OLD_instructions) /. float_of_int minimal_OLD_instructions *. 100.0,
        float_of_int (minimal_NEW_cycles - minimal_OLD_cycles) /. float_of_int minimal_OLD_cycles *. 100.0))

(* [package_name,
    (minimal_NEW_user_time, minimal_NEW_instructions, minimal_NEW_cycles),
    (minimal_OLD_user_time, minimal_OLD_instructions, minimal_OLD_cycles),
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
     (fun (_, (minimal_NEW_user_time,_,_), (minimal_OLD_user_time,_,_), _) ->
        minimal_user_time <= minimal_NEW_user_time && minimal_user_time <= minimal_OLD_user_time)

(* Below we take the measurements and format them to stdout. *)

|> fun measurements ->
     let precision = 2 in

     (* the labels that we will print *)
     let package_name__label = "package_name" in
     let new__label = "NEW" in
     let old__label = "OLD" in
     let proportional_difference__label = "PDIFF" in

     (* the lengths of labels that we will print *)
     let new__label__length = String.length new__label in
     let old__label__length = String.length old__label in
     let proportional_difference__label__length = String.length proportional_difference__label in

     (* widths of individual columns of the table *)
     let package_name__width = max (measurements |> List.map (Tuple4.first %> String.length) |> List.reduce max)
                                   (String.length package_name__label) in
     let new__user_time__width = max ((measurements |> List.map (Tuple4.second %> Tuple3.first)
                                       |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                       new__label__length in
     let new__instructions__width = max (measurements |> List.map (Tuple4.second %> Tuple3.second)
                                         |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                        new__label__length in
     let new__cycles__width = max (measurements |> List.map (Tuple4.second %> Tuple3.third)
                                   |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                  new__label__length in
     let old__user_time__width = max ((measurements |> List.map (Tuple4.third %> Tuple3.first)
                                       |> List.reduce max |> log10 |> ceil |> int_of_float) + 1 + precision)
                                     old__label__length in
     let old__instructions__width = max (measurements |> List.map (Tuple4.third %> Tuple3.second)
                                          |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                          old__label__length in
     let old__cycles__width = max (measurements |> List.map (Tuple4.third %> Tuple3.third)
                                   |> List.reduce max |> float_of_int |> log10 |> ceil |> int_of_float)
                                  old__label__length
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
       (make_dashes new__user_time__width)
       (make_dashes old__user_time__width)
       (make_dashes proportional_difference__user_time__width)
       middle_glyph
       (make_dashes new__cycles__width)
       (make_dashes old__cycles__width)
       (make_dashes proportional_difference__cycles__width)
       middle_glyph
       (make_dashes new__instructions__width)
       (make_dashes old__instructions__width)
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
     ^ center_string "user time [s]" (1 +  new__user_time__width + 1 + old__user_time__width + 1 + proportional_difference__user_time__width + 3) ^ "│"
     ^ center_string "CPU cycles" (1 + new__cycles__width    + 1 + old__cycles__width    + 1 + proportional_difference__cycles__width + 3) ^ "│"
     ^ center_string "CPU instructions" (1 + new__instructions__width + 1 + old__instructions__width + 1 + proportional_difference__instructions__width + 3)
     ^ "│\n" |> print_string;
     printf "│%*s │ %*s│ %*s│ %*s│\n"
       (1 + package_name__width) ""
       (new__user_time__width    + 1 + old__user_time__width    + 1 + proportional_difference__user_time__width + 3) ""
       (new__cycles__width       + 1 + old__cycles__width       + 1 + proportional_difference__cycles__width + 3) ""
       (new__instructions__width + 1 + old__instructions__width + 1 + proportional_difference__instructions__width + 3) "";
     printf "│ %*s │ %*s %*s %*s   │ %*s %*s %*s   │ %*s %*s %*s   │\n"
       package_name__width package_name__label
       new__user_time__width new__label
       old__user_time__width old__label
       proportional_difference__user_time__width proportional_difference__label
       new__cycles__width new__label
       old__cycles__width old__label
       proportional_difference__cycles__width proportional_difference__label
       new__instructions__width new__label
       old__instructions__width old__label
       proportional_difference__instructions__width proportional_difference__label;
     measurements |> List.iter
         (fun (package_name,
               (new_user_time, new_instructions, new_cycles),
               (old_user_time, old_instructions, old_cycles),
               (proportional_difference__user_time, proportional_difference__instructions, proportional_difference__cycles)) ->
           print_string (vertical_separator "├" "┼" "┤");
           printf "│ %*s │ %*.*f %*.*f %+*.*f %% │ %*d %*d %+*.*f %% │ %*d %*d %+*.*f %% │\n"
             package_name__width package_name
             new__user_time__width precision new_user_time
             old__user_time__width precision old_user_time
             proportional_difference__user_time__width precision proportional_difference__user_time
             new__cycles__width new_cycles
             old__cycles__width old_cycles
             proportional_difference__cycles__width precision proportional_difference__cycles
             new__instructions__width new_instructions
             old__instructions__width old_instructions
             proportional_difference__instructions__width precision proportional_difference__instructions);

print_string (vertical_separator "└" "┴" "┘");
printf "

PDIFF = proportional difference between measurements done for the NEW and the OLD Coq version
      = (NEW_measurement - OLD_measurement) / OLD_measurement * 100%%

NEW = %s
OLD = %s

" new_coq_version old_coq_version;

(* TESTS:

   (* roquableu *)

      (* coq-bench/two_points_on_the_same_branch.sh ~/tmp/a https://github.com/psteckler/coq.git array-loops-experiment 10 coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      (* coq-bench/shared/bench.ml coq-bench/shared/inputs_for_formatting_tests/00-mathcomp-00 10 062afabae15e4d7d96029211effd760d8d730484 37817bb5ac6bb9fa9a4d67a5604a35424f7b343d 0 package_name coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      ┌────────────────────────┬───────────────────────┬─────────────────────────────────────┬─────────────────────────────────────┐
      │                        │     user time [s]     │             CPU cycles              │          CPU instructions           │
      │                        │                       │                                     │                                     │
      │           package_name │    NEW    OLD PDIFF   │           NEW           OLD PDIFF   │           NEW           OLD PDIFF   │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │   coq-mathcomp-algebra │ 212.63 213.44 -0.38 % │  706464058475  709196805165 -0.39 % │  711451702236  712651567085 -0.17 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-character │ 319.23 320.73 -0.47 % │ 1082643740546 1088323627566 -0.52 % │ 1139504493386 1141713412512 -0.19 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │     coq-mathcomp-field │ 583.70 590.71 -1.19 % │ 1990210621655 2015346144557 -1.25 % │ 2296309961124 2306640764467 -0.45 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-fingroup │  74.32  74.85 -0.71 % │  238554660588  241040236784 -1.03 % │  246335263268  246673624198 -0.14 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-solvable │ 241.83 242.75 -0.38 % │  806892494982  810003913076 -0.38 % │  861227921524  862801463112 -0.18 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │  60.36  60.63 -0.45 % │  178116867145  178136150304 -0.01 % │  171282677609  171356983582 -0.04 % │
      └────────────────────────┴───────────────────────┴─────────────────────────────────────┴─────────────────────────────────────┘

      (* coq-bench/two_points_on_the_same_branch.sh ~/tmp/b https://github.com/psteckler/coq.git array-loops-experiment 10 coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      (* coq-bench/shared/bench.ml coq-bench/shared/inputs_for_formatting_tests/00-mathcomp-01 10 062afabae15e4d7d96029211effd760d8d730484 37817bb5ac6bb9fa9a4d67a5604a35424f7b343d 0 package_name coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      ┌────────────────────────┬───────────────────────┬─────────────────────────────────────┬─────────────────────────────────────┐
      │                        │     user time [s]     │             CPU cycles              │          CPU instructions           │
      │                        │                       │                                     │                                     │
      │           package_name │    NEW    OLD PDIFF   │           NEW           OLD PDIFF   │           NEW           OLD PDIFF   │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │   coq-mathcomp-algebra │ 212.52 213.17 -0.30 % │  706686348801  710314147087 -0.51 % │  711073932038  712177435195 -0.15 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-character │ 319.97 321.26 -0.40 % │ 1085064343496 1089308833819 -0.39 % │ 1139118960768 1141357953675 -0.20 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │     coq-mathcomp-field │ 583.52 590.59 -1.20 % │ 1992883675381 2015010888610 -1.10 % │ 2295880307828 2306374766977 -0.46 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-fingroup │  74.11  74.73 -0.83 % │  239488168649  240604829599 -0.46 % │  246000684926  246339110521 -0.14 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │  coq-mathcomp-solvable │ 241.69 242.31 -0.26 % │  807003389584  809675678158 -0.33 % │  860942356537  862419797782 -0.17 % │
      ├────────────────────────┼───────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │  60.57  60.07 +0.83 % │  178177984751  178124701650 +0.03 % │  170948226776  171013670382 -0.04 % │
      └────────────────────────┴───────────────────────┴─────────────────────────────────────┴─────────────────────────────────────┘

   (* marelle1 *)

      (* d=~/tmp/d; rm -r -f $d; mkdir $d; date > $d.date; ./two_versions.sh $d 8.6 8.5.3 10 coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} | tee $d.out; date >> $d.date *)

      (* ./two_versions.sh /tmp 8.6 8.5.3 10 coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      (* coq-bench/shared/bench.ml coq-bench/shared/inputs_for_formatting_tests/02-mathcomp-00 10 8.6 8.5.3 0 user_time_pdiff coq-mathcomp-{algebra,character,field,fingroup,solvable,ssreflect} *)

      ┌────────────────────────┬────────────────────────┬──────────────────────────────────────┬──────────────────────────────────────┐
      │                        │     user time [s]      │              CPU cycles              │           CPU instructions           │
      │                        │                        │                                      │                                      │
      │           package_name │    NEW    OLD  PDIFF   │           NEW           OLD  PDIFF   │           NEW           OLD  PDIFF   │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │     coq-mathcomp-field │ 501.46 794.42 -36.88 % │ 1889816800662 3000863974008 -37.02 % │ 2296192581264 3178649847387 -27.76 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │ coq-mathcomp-character │ 266.32 383.05 -30.47 % │ 1001342364413 1444675626207 -30.69 % │ 1131173310898 1455579092507 -22.29 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │   coq-mathcomp-algebra │ 174.10 244.55 -28.81 % │  652926709081  919498603517 -28.99 % │  699634939597  929248877879 -24.71 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │  coq-mathcomp-solvable │ 198.02 270.42 -26.77 % │  740915123132 1016390411097 -27.10 % │  850143460082 1069979792475 -20.55 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │ coq-mathcomp-ssreflect │  43.30  58.36 -25.81 % │  157895171870  215437277471 -26.71 % │  156938887589  211916125534 -25.94 % │
      ├────────────────────────┼────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
      │  coq-mathcomp-fingroup │  57.09  70.39 -18.89 % │  211574889864  261327328228 -19.04 % │  232001619180  274457482721 -15.47 % │
      └────────────────────────┴────────────────────────┴──────────────────────────────────────┴──────────────────────────────────────┘

      (* d=~/tmp/a; rm -r -f $d; mkdir $d; date > $d.date; ./stdlib.sh $d https://github.com/coq/coq.git V8.6 V8.5pl3 10 | tee $d.out; date >> $d.date *)

      (* coq-bench/stdlib.sh ~/tmp/a https://github.com/coq/coq.git V8.6 V8.5pl3 10 *)

      (* coq-bench/shared/bench.ml coq-bench/shared/inputs_for_formatting_tests/03-stdlib 10 8.6 8.5.3 0 package_name stdlib *)

      (* Sat Jan 21 16:57:04 CET 2017
         Sat Jan 21 19:44:31 CET 2017 *)

      ┌──────────────┬────────────────────────┬─────────────────────────────────────┬─────────────────────────────────────┐
      │              │     user time [s]      │             CPU cycles              │          CPU instructions           │
      │              │                        │                                     │                                     │
      │ package_name │    NEW    OLD  PDIFF   │           NEW           OLD PDIFF   │           NEW           OLD PDIFF   │
      ├──────────────┼────────────────────────┼─────────────────────────────────────┼─────────────────────────────────────┤
      │       stdlib │ 385.71 452.74 -14.81 % │ 1444996061570 1589989599510 -9.12 % │ 1484837046549 1615010725676 -8.06 % │
      └──────────────┴────────────────────────┴─────────────────────────────────────┴─────────────────────────────────────┘

*)
